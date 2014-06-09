local lock = require "resty.lock"
local cjson = require "cjson.safe"

local tab_insert = table.insert
local str_sub = string.sub
local ERR = ngx.ERR
local WARN = ngx.WARN
local tcp = ngx.socket.tcp
local mutex = ngx.shared.mutex
local state = ngx.shared.state
local localtime = ngx.localtime
local re_find = ngx.re.find


local _M = {
    _VERSION = "0.0.1",
    STATUS_OK = 0,
    STATUS_ERR = 1,
}

local CHECKUP_TIMER_KEY = "checkups:timer"
local CHECKUP_HEALTH_KEY = "checkups:health"

local PEER_STATUS_PREFIX = "peer_status:"
local PEER_FAIL_COUNTER_PREFIX = "peer_fail_counter:"
local CLS_LAST_CHECK_TIME_PREFIX = "cls_last_check_time:"

local upstream = {}


local function get_lock(key)
    local lock = lock:new("locks")
    local elapsed, err = lock:lock(key)
    if not elapsed then
        ngx.log(WARN, "failed to acquire the lock: " .. key .. ', ' .. err)
        return nil, err
    end

    return lock
end


local function release_lock(lock)
    local ok, err = lock:unlock()
    if not ok then
        ngx.log(ngx.WARN, "failed to unlock: ", err)
    end
end


local function update_peer_status(peer_key, status, msg, time)
    local status_key = PEER_STATUS_PREFIX .. peer_key

    local old_status, err = state:get(status_key)
    if err then
        ngx.log(ERR, "get old status " .. status_key .. ' ' .. err)
        return
    end

    if not old_status then
        old_status = {}
    else
        old_status = cjson.decode(old_status)
    end

    if old_status.status ~= status then
        old_status.status = status
        old_status.msg = msg
        old_status.lastmodified = time
        local ok, err = state:set(status_key, cjson.encode(old_status))
        if not ok then
            ngx.log(ERR, "failed to set new status " .. err)
        end
    end
end


local function update_peer_status_locked(peer_key, status, msg, time)
    local lock = get_lock(CHECKUP_HEALTH_KEY)
    if not lock then
        return
    end

    update_peer_status(peer_key, status, msg, time)

    release_lock(lock)
end


local function get_fail_counter_locked(peer_key)
    local counter_key = PEER_FAIL_COUNTER_PREFIX .. peer_key

    local lock = get_lock(CHECKUP_HEALTH_KEY)
    if not lock then
        return
    end

    local fail_num, err = state:get(counter_key)
    if err then
        ngx.log(ERR, "get fail_num " .. counter_key .. ' ' .. err)
    end

    release_lock(lock)

    return fail_num or 0
end


local function clear_fail_counter_locked(peer_key)
    local counter_key = PEER_FAIL_COUNTER_PREFIX .. peer_key

    local lock = get_lock(CHECKUP_HEALTH_KEY)
    if not lock then
        return
    end

    local ok, err = state:set(counter_key, 0)
    if not ok then
        ngx.log(ERR, "failed to clear fail_num " .. err)
    end

    release_lock(lock)
end


local function increase_fail_counter_locked(peer_key, ups_max_fails)
    local counter_key = PEER_FAIL_COUNTER_PREFIX .. peer_key

    local lock = get_lock(CHECKUP_HEALTH_KEY)
    if not lock then
        return
    end

    local fail_num, err = state:get(counter_key)
    if err then
        release_lock(lock)
        ngx.log(ERR, "get fail_num " .. counter_key .. ' ' .. err)
        return
    end

    if not fail_num then
        fail_num = 1
    else
        fail_num = fail_num + 1
    end

    local ok, err = state:set(counter_key, fail_num)
    if not ok then
        ngx.log(ERR, "failed to set fail_num " .. err)
        release_lock(lock)
        return
    end

    if fail_num >= ups_max_fails then
        update_peer_status(peer_key, _M.STATUS_ERR, "max fail exceeded",
            localtime())
    end

    release_lock(lock)
end


function _M.ready_ok(skey, callback)
    local ups = upstream.checkups[skey]
    if not ups then
        ngx.log(ERR, "unknown skey " .. skey)
        return nil, "unknown skey " .. skey
    end

    local ups_max_fails = ups.max_fails

    for level, cls in ipairs(ups.cluster) do
        local counter = cls.counter

        local idx = counter() -- pre request load-balancing with round-robin
        local try = cls.try or #cls.servers
        local len_servers = #cls.servers

        for i=1, len_servers, 1 do
            local srv = cls.servers[idx]
            local key = srv.host .. ":" .. tostring(srv.port)
            local peer_status = cjson.decode(state:get(PEER_STATUS_PREFIX .. key))

            if peer_status == nil or peer_status.status == _M.STATUS_OK then
                local res = callback(srv.host, srv.port)
                if res then
                    return res
                end

                if upstream.passive_check then
                    increase_fail_counter_locked(key, ups_max_fails)
                end

                try = try - 1
                if try < 1 then -- max try times
                    return nil, "max try exceeded"
                end
            end
            idx = idx % len_servers + 1
        end
    end

    return nil, "no upstream available"
end


local heartbeat = {
    general = function (host, port, timeout, opts)
        local sock = tcp()
        sock:settimeout(timeout * 1000)
        local ok, err = sock:connect(host, port)
        if not ok then
            ngx.log(ERR, "failed to connect: ", host, ":",
                    tostring(port), " ", err)
            return _M.STATUS_ERR, err
        end

        sock:setkeepalive()

        return _M.STATUS_OK
    end,

    redis = function (host, port, timeout, opts)
        local ok, redis = pcall(require, "resty.redis")
        if not ok then
            ngx.log(ERR, 'failed to require redis')
            return _M.STATUS_ERR, 'failed to require redis'
        end

        local red = redis:new()

        red:set_timeout(timeout * 1000)

        local ok, err = red:connect(host, port)
        if not ok then
            ngx.log(ERR, "failed to connect redis: ", err)
            return _M.STATUS_ERR, err
        end

        local res, err = red:ping()
        if not res then
            ngx.log(ERR, "failed to ping redis: ", err)
            return _M.STATUS_ERR, err
        end

        red:set_keepalive(10000, 100)

        return _M.STATUS_OK
    end,

    mysql = function (host, port, timeout, opts)
        local ok, mysql = pcall(require, "resty.mysql")
        if not ok then
            ngx.log(ERR, 'failed to require mysql')
            return _M.STATUS_ERR, 'failed to require mysql'
        end

        local db, err = mysql:new()
        if not db then
            ngx.log(WARN, "failed to instantiate mysql: ", err)
            return _M.STATUS_ERR, err
        end

        db:set_timeout(timeout * 1000)

        local ok, err, errno, sqlstate = db:connect{
            host = host,
            port = port,
            database = opts.name,
            user = opts.user,
            password = opts.pass,
            max_packet_size = 1024*1024
        }

        if not ok then
            ngx.log(ERR, "faild to connect: ", err, ": ", errno,
                    " ", sqlstate)
            return _M.STATUS_ERR, err
        end

        db:set_keepalive(10000, 100)

        return _M.STATUS_OK
    end,

    http = function(host, port, timeout, opts)
        local sock = tcp()
        sock:settimeout(timeout * 1000)
        local ok, err = sock:connect(host, port)
        if not ok then
            ngx.log(ERR, "failed to connect: ", host, ":",
                    tostring(port), " ", err)
            return _M.STATUS_ERR, err
        end

        local req = opts.query
        if not req then
            ngx.log(ERR, "http upstream has no query string")
            return _M.STATUS_ERR
        end

        local bytes, err = sock:send(req)
        if not bytes then
            ngx.log(ERR, "failed to send request to ", host, ": ", err)
            return _M.STATUS_ERR, err
        end

        local readline = sock:receiveuntil("\r\n")
        local status_line, err = readline()
        if not status_line then
            ngx.log(ERR, "failed to receive status line from ",
                host, ":", port, ": ", err)
            return _M.STATUS_ERR, err
        end

        local statuses = opts.statuses
        if statuses then
            local from, to, err = re_find(status_line,
                [[^HTTP/\d+\.\d+\s+(\d+)]], "joi", nil, 1)
            if not from then
                ngx.log(ERR, "bad status line from ", host, ": ", err)
                return _M.STATUS_ERR, err
            end

            local status = tonumber(str_sub(status_line, from, to))
            if not statuses[status] then
                return _M.STATUS_ERR, "bad status code"
            end
        end

        sock:setkeepalive()

        return _M.STATUS_OK
    end,
}


local function cluster_heartbeat(skey)
    local ups = upstream.checkups[skey]
    local ups_timeout = ups.timeout or 60
    local ups_typ = ups.typ or "general"
    local ups_heartbeat = ups.heartbeat
    local ups_opts = ups.heartbeat_opts or {}

    for level, cls in ipairs(ups.cluster) do
        for id, srv in ipairs(cls.servers) do
            local status = _M.STATUS_ERR
            local key = srv.host .. ":" .. tostring(srv.port)
            local cb_heartbeat = ups_heartbeat or heartbeat[ups_typ]
            local ok, err = cb_heartbeat(srv.host, srv.port, ups_timeout, ups_opts)
            if ok == _M.STATUS_OK then
                local fail_num = get_fail_counter_locked(skey, key)
                if fail_num > 0 then
                    clear_fail_counter_locked(key)
                end
                status = _M.STATUS_OK
            end
            update_peer_status_locked(key, status, err or cjson.null, localtime())
        end
    end

    state:set(CLS_LAST_CHECK_TIME_PREFIX .. skey, localtime())
end


local function active_checkup(premature)
    local ckey = CHECKUP_TIMER_KEY

    ngx.update_time() -- flush cache time

    if premature then
        local ok, err = mutex:set(ckey, nil)
        if not ok then
            ngx.log(WARN, "failed to update shm: ", err)
        end
        return
    end

    for skey in pairs(upstream.checkups) do
        cluster_heartbeat(skey)
    end

    local interval = upstream.checkup_timer_interval
    local overtime = upstream.checkup_timer_overtime

    local ok, err = mutex:set(ckey, 1, overtime)
    if not ok then
        ngx.log(WARN, "failed to update shm: ", err)
    end

    local ok, err = ngx.timer.at(interval, active_checkup)
    if not ok then
        ngx.log(WARN, "failed to create timer: ", err)
        local ok, err = mutex:set(ckey, nil)
        if not ok then
            ngx.log(WARN, "failed to update shm: ", err)
        end
        return
    end
end

local function table_dup(ori_tab)
    if type(ori_tab) ~= "table" then
        return ori_tab
    end
    local new_tab = {}
    for k, v in pairs(ori_tab) do
        if type(v) == "table" then
            new_tab[k] = table_dup(v)
        else
            new_tab[k] = v
        end
    end
    return new_tab
end


function _M.prepare_checker(config)
    local function counter(max)
        local i = 0
        return function ()
            if max > 0 then
                i = i % max + 1
            end
            return i
        end
    end

    upstream.positive_check = config.global.positive_check
    upstream.passive_check = config.global.passive_check
    upstream.checkup_timer_interval = config.global.checkup_timer_interval
    upstream.checkup_timer_overtime = config.global.checkup_timer_overtime
    upstream.checkups = {}

    for skey, ups in pairs(config) do
        if type(ups) == "table" and ups.cluster and #ups.cluster > 0
            and (ups.typ and heartbeat[ups.typ] or ups.heartbeat) then
            upstream.checkups[skey] = table_dup(ups)
            for level, cls in ipairs(upstream.checkups[skey].cluster) do
                cls.counter = counter(#cls.servers)
            end
        end
    end

    upstream.initialized = true
end


local function get_upstream_status(skey)
    local ups = upstream.checkups[skey]
    if not ups then
        return {}
    end

    local ups_status = {}
    for level, cls in ipairs(ups.cluster) do
        local servers = cls.servers
        ups_status[level] = {}
        if servers and type(servers) == "table" and #servers > 0 then
            for id, srv in ipairs(servers) do
                local key = srv.host .. ":" .. tostring(srv.port)
                local peer_status = cjson.decode(state:get(PEER_STATUS_PREFIX .. key)) or {}
                peer_status.id = id
                peer_status.fail_num = get_fail_counter_locked(key)
                tab_insert(ups_status[level], peer_status)
            end
        end
    end

    return ups_status
end


function _M.get_status()
    local all_status = {}
    for skey in pairs(upstream.checkups) do
        all_status[skey] = get_upstream_status(skey)
    end

    return cjson.encode(all_status)
end


function _M.create_checker()
    if not upstream.positive_check then
        return
    end

    local ckey = CHECKUP_TIMER_KEY
    local val, err = mutex:get(ckey)
    if val then
        return
    end

    if err then
        ngx.log(WARN, "failed to get key from shm: ", err)
        return
    end

    if not upstream.initialized then
        ngx.log(ERR, "create checker failed, call prepare_checker in init_by_lua")
        return
    end

    local lock = get_lock(ckey)
    if not lock then
        return ngx.log(WARN, "failed to acquire the lock: ", err)
    end

    val, err = mutex:get(ckey)
    if val then
        release_lock(ckey)
        return
    end

    -- create active checkup timer
    local ok, err = ngx.timer.at(0, active_checkup)
    if not ok then
        ngx.log(ngx.WARN, "failed to create timer: ", err)
        return
    end

    local overtime = upstream.checkup_timer_overtime
    local ok, err = mutex:set(ckey, 1, overtime)
    if not ok then
        release_lock(lock)
        ngx.log(WARN, "failed to update shm: ", err)
        return
    end

    release_lock(lock)
end

return _M
