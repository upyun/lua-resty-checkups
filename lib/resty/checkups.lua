local lock = require "resty.lock"
local cjson = require "cjson.safe"

local ERR = ngx.ERR
local INFO = ngx.INFO
local WARN = ngx.WARN
local tcp = ngx.socket.tcp
local mutex = ngx.shared.mutex
local state = ngx.shared.state
local localtime = ngx.localtime


local _M = {
    _VERSION = "0.0.1",
    STATUS_OK = 0,
    STATUS_ERR = 1,
}

local CHECKUP_TIMER_KEY = "checkups:timer"
local CHECKUP_FAIL_COUNTER_KEY = "checkups:fail_counter"

local upstream = {}


local function get_fail_counter(skey, key)
    local counter_key = skey .. key

    local lock = lock:new("locks")
    local elapsed, err = lock:lock(CHECKUP_FAIL_COUNTER_KEY)
    if not elapsed then
        ngx.log(WARN, "failed to acquire the lock: ", err)
        return nil, err
    end

    local fail_num, err = state:get(counter_key)
    if err then
        ngx.log(ERR, "get fail_num " .. counter_key .. ' ' .. err)
    end

    local ok, err = lock:unlock()
    if not ok then
        ngx.log(ngx.WARN, "failed to unlock: ", err)
    end

    return fail_num or 0
end


local function update_fail_counter(skey, key, set)
    local counter_key = skey .. key

    local lock = lock:new("locks")
    local elapsed, err = lock:lock(CHECKUP_FAIL_COUNTER_KEY)
    if not elapsed then
        ngx.log(WARN, "failed to acquire the lock: ", err)
        return
    end

    local fail_num, err = state:get(counter_key)
    if err then
        local ok, err = lock:unlock()
        if not ok then
            ngx.log(ngx.WARN, "failed to unlock: ", err)
        end
        ngx.log(ERR, "get fail_num " .. counter_key .. ' ' .. err)
        return
    end

    if set then
        fail_num = set
    elseif not fail_num then
        fail_num = 1
    else
        fail_num = fail_num + 1
    end

    local ok, err = state:set(counter_key, fail_num)
    if not ok then
        ngx.log(ERR, "failed to set fail_num " .. err)
    end

    local ok, err = lock:unlock()
    if not ok then
        ngx.log(ngx.WARN, "failed to unlock: ", err)
    end
end


function _M.ready_ok(skey, callback)
    local cluster_state = cjson.decode(state:get(skey .. ":cluster")) or {}
    local ups = upstream.checkups[skey]
    local ups_max_fail = ups.max_fail

    for level, cls in ipairs(ups.cluster) do
        local counter = cls.counter
        local cls_state = cluster_state[level] or {}

        local idx = counter() -- pre request load-balancing with round-robin
        local try = cls.try or #cls.servers
        local len_servers = #cls.servers

        for i=1, len_servers, 1 do
            local srv = cls.servers[idx]
            local key = srv.host .. ":" .. tostring(srv.port)
            local fail_num = get_fail_counter(skey, key)

            -- positive check and passive check both passed
            if (cls_state[key] == nil or cls_state[key].status == "ok")
                and fail_num < ups_max_fail then
                local ok, err = callback(srv.host, srv.port)
                if ok == _M.STATUS_OK then
                    return _M.STATUS_OK
                end

                if err then
                    update_fail_num(skey, key)
                end

                try = try - 1
                if try < 1 then -- max try times
                    return _M.STATUS_ERR, "max try exceeded"
                end
            end
            idx = idx % len_servers + 1
        end
    end

    return _M.STATUS_ERR, "no upstream avalable"
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

        ok, err = sock:setkeepalive()

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
}


local function cluster_heartbeat(skey)
    local cluster_key = skey .. ":cluster"
    local cluster_state = cjson.decode(state:get(cluster_key)) or {}

    local ups = upstream.checkups[skey]
    local ups_timeout = ups.timeout
    local ups_typ = ups.typ or "general"
    local ups_heartbeat = ups.heartbeat
    local ups_opts = ups.opts
    local need_update = false

    for level, cls in ipairs(ups.cluster) do
        if not cluster_state[level] then
            need_update = true
            cluster_state[level] = {}
        end
        for id, srv in ipairs(cls.servers) do
            local status = "err"
            local key = srv.host .. ":" .. tostring(srv.port)
            local cb_heartbeat = ups_heartbeat or heartbeat[ups_typ]
            local ok, err = cb_heartbeat(srv.host, srv.port, ups_timeout, opts)
            if ok == _M.STATUS_OK then
                update_fail_counter(skey, key, 0)
                status = "ok"
            end
            local old_state = cluster_state[level][key]
            if not old_state or old_state.status ~= status then
                cluster_state[level][key] = {
                    id = id,
                    status = status,
                    msg = err or cjson.null,
                    lastmodified = localtime(),
                }
                need_update = true
            end
        end
    end

    if need_update then
        state:set(cluster_key, cjson.encode(cluster_state))
    end
    state:set(cluster_key .. ":lastchecktime", cjson.encode(localtime()))
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


function _M.create_checker()
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

    local lock = lock:new("locks")
    local elapsed, err = lock:lock(ckey)
    if not elapsed then
        return ngx.log(WARN, "failed to acquire the lock: ", err)
    end

    val, err = mutex:get(ckey)
    if val then
        local ok, err = lock:unlock()
        if not ok then
            ngx.log(WARN, "failed to unlock: ", err)
            return
        end
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
        local ok, err = lock:unlock()
        if not ok then
            ngx.log(WARN, "failed to unlock: ", err)
            return
        end

        ngx.log(WARN, "failed to update shm: ", err)
        return
    end

    local ok, err = lock:unlock()
    if not ok then
        ngx.log(WARN, "failed to unlock: ", err)
    end
end

return _M
