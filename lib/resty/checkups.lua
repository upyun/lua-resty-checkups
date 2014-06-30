-- Copyright (C) 2014 Jing Ye (yejingx), UPYUN Inc.
-- Copyright (C) 2014 Monkey Zhang (timebug), UPYUN Inc.

local lock = require "resty.lock"
local cjson = require "cjson.safe"

local ERR = ngx.ERR
local WARN = ngx.WARN
local str_sub = string.sub
local tcp = ngx.socket.tcp
local re_find = ngx.re.find
local mutex = ngx.shared.mutex
local state = ngx.shared.state
local localtime = ngx.localtime
local tab_insert = table.insert


local _M = { _VERSION = "0.02", STATUS_OK = 0, STATUS_ERR = 1 }

local CHECKUP_TIMER_KEY = "checkups:timer"
local CHECKUP_ACC_FAILS_KEY = "checkups:acc_fails"
local CHECKUP_LAST_CHECK_TIME_KEY = "checkups:last_check_time"
local CHECKUP_TIMER_ALIVE_KEY = "checkups:timer_alive"

local PEER_STATUS_PREFIX = "peer_status:"
local PEER_FAIL_COUNTER_PREFIX = "peer_fail_counter:"

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
    if status ~= _M.STATUS_OK and status ~= _M.STATUS_ERR then
        return
    end

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
        if status == _M.STATUS_ERR then
            local counter_key = PEER_FAIL_COUNTER_PREFIX .. peer_key
            local ok, err = state:set(counter_key, 0)
            if not ok then
                ngx.log(ERR, "failed to clear acc fail counter: ", err)
            end
        end

        old_status.status = status
        old_status.msg = msg
        old_status.lastmodified = time
        local ok, err = state:set(status_key, cjson.encode(old_status))
        if not ok then
            ngx.log(ERR, "failed to set new status " .. err)
        end
    end
end


local function get_acc_fail_counter(peer_key)
    local counter_key = PEER_FAIL_COUNTER_PREFIX .. peer_key

    local acc_fail_num, err = state:get(counter_key)
    if err then
        ngx.log(ERR, "get acc_fail_num " .. counter_key .. ' ' .. err)
    end

    return acc_fail_num or 0
end


local function increase_acc_fail_counter(peer_key)
    local counter_key = PEER_FAIL_COUNTER_PREFIX .. peer_key

    local succ, err = state:add(counter_key, 1)
    if succ == true then
        return
    elseif succ == false and err == "exists" then
        local ok, err = state:incr(counter_key, 1)
        if not ok then
            ngx.log(ERR, "failed to set acc_fail_num " .. err)
            return
        end
    else
        ngx.log(ERR, "add acc_fail_num " .. counter_key .. ' ' .. err)
        return
    end
end


local function try_cluster(ups, cls, callback)
    local counter = cls.counter

    local idx = counter() -- pre request load-balancing with round-robin
    local try = cls.try or #cls.servers
    local len_servers = #cls.servers

    for i=1, len_servers, 1 do
        local srv = cls.servers[idx]
        local key = srv.host .. ":" .. tostring(srv.port)
        local peer_status = cjson.decode(state:get(PEER_STATUS_PREFIX
                                                       .. key))
        if peer_status == nil or peer_status.status == _M.STATUS_OK then
            local res, err = callback(srv.host, srv.port)

            if res then
                local pass = true
                local ups_type = ups.typ

                if ups_type == "http" and type(res) == "table"
                    and res.status then
                    local status = tonumber(res.status)
                    local opts = ups.http_opts
                    if opts and opts.statuses and
                    opts.statuses[status] == false then
                        pass = false
                    end
                end

                if pass then
                    return res
                end
            end

            increase_acc_fail_counter(key)

            try = try - 1
            if try < 1 then -- max try times
                return res, err
            end
        end
        idx = idx % len_servers + 1
    end

    -- continue to next level
    if try > 0 then
        return nil, nil, true
    end
end


function _M.ready_ok(skey, callback, cluster_key)
    local ups = upstream.checkups[skey]
    if not ups then
        return nil, "unknown skey " .. skey
    end

    local res, err, cont

    -- try by key
    if cluster_key then
        local cls = ups.cluster[cluster_key]
        if cls then
            res, err = try_cluster(ups, cls, callback)
            if res then
                return res, err
            end
        end
        return res, err
    end

    -- try by level
    for level, cls in ipairs(ups.cluster) do
        res, err, cont = try_cluster(ups, cls, callback)
        if res then
            return res, err
        end

        -- continue to next level?
        if not cont then
            break
        end
    end

    if not err then
        err = "no upstream available"
    end

    return nil, err
end


local heartbeat = {
    general = function (host, port, ups)
        local sock = tcp()
        sock:settimeout(ups.timeout * 1000)
        local ok, err = sock:connect(host, port)
        if not ok then
            ngx.log(ERR, "failed to connect: ", host, ":",
                    tostring(port), " ", err)
            return _M.STATUS_ERR, err
        end

        sock:setkeepalive()

        return _M.STATUS_OK
    end,

    redis = function (host, port, ups)
        local ok, redis = pcall(require, "resty.redis")
        if not ok then
            ngx.log(ERR, 'failed to require redis')
            return _M.STATUS_ERR, 'failed to require redis'
        end

        local red = redis:new()

        red:set_timeout(ups.timeout * 1000)

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

    mysql = function (host, port, ups)
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

        db:set_timeout(ups.timeout * 1000)

        local ok, err, errno, sqlstate = db:connect{
            host = host,
            port = port,
            database = ups.name,
            user = ups.user,
            password = ups.pass,
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

    http = function(host, port, ups)
        local sock = tcp()
        sock:settimeout(ups.timeout * 1000)
        local ok, err = sock:connect(host, port)
        if not ok then
            ngx.log(ERR, "failed to connect: ", host, ":",
                    tostring(port), " ", err)
            return _M.STATUS_ERR, err
        end

        local opts = ups.http_opts or {}

        local req = opts.query
        if not req then
            sock:setkeepalive()
            return _M.STATUS_OK
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
            if statuses[status] == false then
                return _M.STATUS_ERR, "bad status code"
            end
        end

        sock:setkeepalive()

        return _M.STATUS_OK
    end,
}


local function cluster_heartbeat(skey)
    local ups = upstream.checkups[skey]
    local ups_typ = ups.typ or "general"
    local ups_heartbeat = ups.heartbeat

    ups.timeout = ups.timeout or 60

    for level, cls in pairs(ups.cluster) do
        for id, srv in ipairs(cls.servers) do
            local key = srv.host .. ":" .. tostring(srv.port)
            local cb_heartbeat = ups_heartbeat or heartbeat[ups_typ] or
                heartbeat["general"]
            local status, err = cb_heartbeat(srv.host, srv.port, ups)
            update_peer_status(key, status, err or cjson.null, localtime())
        end
    end

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

    state:set(CHECKUP_LAST_CHECK_TIME_KEY, localtime())
    state:set(CHECKUP_TIMER_ALIVE_KEY, true, overtime)

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

        if type(ups) == "table" and ups.cluster
            and type(ups.cluster) == "table" then
            upstream.checkups[skey] = table_dup(ups)
            for level, cls in pairs(upstream.checkups[skey].cluster) do
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

    for level, cls in pairs(ups.cluster) do
        local servers = cls.servers
        ups_status[level] = {}
        if servers and type(servers) == "table" and #servers > 0 then
            for id, srv in ipairs(servers) do
                local key = srv.host .. ":" .. tostring(srv.port)
                local peer_status = cjson.decode(state:get(PEER_STATUS_PREFIX ..
                                                               key)) or {}
                peer_status.server = key
                peer_status.acc_fail_num = get_acc_fail_counter(key)
                if not peer_status.status or
                peer_status.status == _M.STATUS_OK then
                    peer_status.status = "ok"
                else
                    peer_status.status = "err"
                end
                tab_insert(ups_status[level], peer_status)
            end
        end
    end

    return ups_status
end


function _M.get_status()
    local all_status = {}
    for skey in pairs(upstream.checkups) do
        all_status["cls:" .. skey] = get_upstream_status(skey)
    end
    local last_check_time = state:get(CHECKUP_LAST_CHECK_TIME_KEY) or cjson.null
    all_status.last_check_time = last_check_time
    all_status.checkup_timer_alive = state:get(CHECKUP_TIMER_ALIVE_KEY) or false

    return all_status
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
        ngx.log(ERR,
                "create checker failed, call prepare_checker in init_by_lua")
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
