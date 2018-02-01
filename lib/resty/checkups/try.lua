-- Copyright (C) 2014-2016, UPYUN Inc.

local round_robin     = require "resty.checkups.round_robin"
local consistent_hash = require "resty.checkups.consistent_hash"
local base            = require "resty.checkups.base"

local type       = type
local ipairs     = ipairs
local tostring   = tostring
local tab_insert = table.insert
local str_sub    = string.sub
local str_find   = string.find
local str_format = string.format

local now           = ngx.now
local log           = ngx.log
local ERR           = ngx.ERR

local _M = { _VERSION = "0.11" }

local is_tab = base.is_tab

local NEED_RETRY       = 0
local REQUEST_SUCCESS  = 1
local EXCESS_TRY_LIMIT = 2
local RETRY_DONE       = 3

_M.NEED_RETRY = NEED_RETRY
_M.RETRY_DONE = RETRY_DONE
_M.REQUEST_SUCCESS = REQUEST_SUCCESS
_M.EXCESS_TRY_LIMIT = EXCESS_TRY_LIMIT

local reg = {
    hash = consistent_hash,
    default = round_robin,
}

function _M.register(name, module)
    if type(name) ~= "string" or str_find(name, "_") then
        return false, "invalid name"
    end

    if type(module) ~= "table" then
        return false, "invalid module"
    end

    if not module.ipairsrvs and not module.itercls then
        return false, "invalid module"
    end

    reg[name] = module
    return true
end


function _M.unregister(name)
    reg[name] = nil
    return true
end


local function default_retry(ups, try_limit)
    local statuses
    if ups.typ == "http" and is_tab(ups.http_opts) then
        statuses = ups.http_opts.statuses
    end
    local try_cnt = 0
    local retry_cb = function(res)
        if is_tab(res) and res.status and is_tab(statuses) then
            if statuses[tostring(res.status)] ~= false then
                return REQUEST_SUCCESS
            end
        elseif res then
            return REQUEST_SUCCESS
        end

        try_cnt = try_cnt + 1
        if try_cnt >= try_limit then
            return EXCESS_TRY_LIMIT
        end

        return NEED_RETRY
    end
    return retry_cb
end



local function prepare_callbacks(skey, ups, opts, module)
    -- calculate count of cluster and server
    local cls_keys = {}  -- string key or number level
    local srvs_cnt = 0
    if is_tab(opts.cluster_key) then  -- specify try cluster
        for _, cls_key in ipairs(opts.cluster_key) do
            local cls = ups.cluster[cls_key]
            if is_tab(cls) then
                tab_insert(cls_keys, cls_key)
                srvs_cnt = srvs_cnt + #cls.servers
            end
        end
    else  -- default try cluster
        for cls_key, cls in pairs(ups.cluster) do
            tab_insert(cls_keys, cls_key)
            srvs_cnt = srvs_cnt + #cls.servers
        end
    end

    -- get next level cluster
    local cls_key
    local cls_index = 0
    local cls_cnt = #cls_keys
    local next_cluster_cb = function()
        cls_index = cls_index + 1
        if cls_index > cls_cnt then
            return
        end

        cls_key = cls_keys[cls_index]
        return ups.cluster[cls_key]
    end

    local try_limit
    if module.try_limit then
        try_limit = module.try_limit(ups, opts)
    else
        try_limit = opts.try or ups.try
    end

    try_limit = try_limit or srvs_cnt

    -- check whether ther server is available
    local bad_servers = {}
    local peer_cb = function(index, srv)
        local key = ("%s:%s:%s"):format(cls_key, srv.host, srv.port)
        if bad_servers[key] then
            return false
        end

        if ups.enable == false or (ups.enable == nil
            and base.upstream.default_heartbeat_enable == false) then
            return base.get_srv_status(skey, srv) == base.STATUS_OK
        end

        local peer_status = base.get_peer_status(skey, srv)
        if (not peer_status or peer_status.status ~= base.STATUS_ERR)
        and base.get_srv_status(skey, srv) == base.STATUS_OK then
            return true
        end
    end

    local retry_func = module.retry_cb or default_retry
    local retry_cb = retry_func(ups, try_limit)
    -- check whether try_time has over amount_request_time
    local try_time = 0
    local try_time_limit = opts.try_timeout or ups.try_timeout or 0
    local try_time_cb = function(this_time_try_time)
        try_time = try_time + this_time_try_time
        if try_time_limit == 0 then
            return NEED_RETRY
        elseif try_time >= try_time_limit then
            return EXCESS_TRY_LIMIT
        end

        return NEED_RETRY
    end

    -- set some status
    local set_status_cb = function(srv, failed)
        local key = ("%s:%s:%s"):format(cls_key, srv.host, srv.port)
        bad_servers[key] = failed
        base.set_srv_status(skey, srv, failed)
        if module.free_server then
            module.free_server(srv, failed)
        end
    end

    return {
        next_cluster_cb = next_cluster_cb,
        retry_cb = retry_cb,
        peer_cb = peer_cb,
        set_status_cb = set_status_cb,
        try_time_cb = try_time_cb,
    }
end



--[[
parameters:
    - (string) skey
    - (function) request_cb(host, port)
    - (table) opts
        - (number) try
        - (table) cluster_key
        - (string) hash_key
return:
    - (string) result
    - (string) error
--]]
function _M.try_cluster(skey, request_cb, opts)
    local ups = base.upstream.checkups[skey]
    local mode = ups.mode or "default"
    local _, to = str_find(mode, "_")
    if to then
       mode = str_sub(mode, to + 1)
    end
    local module = reg[mode]
    print("mode:", mode, ", module:", tostring(module))
    local callbacks = prepare_callbacks(skey, ups, opts, module)

    local next_cluster_cb = callbacks.next_cluster_cb
    local peer_cb         = callbacks.peer_cb
    local retry_cb        = callbacks.retry_cb
    local set_status_cb   = callbacks.set_status_cb
    local try_time_cb     = callbacks.try_time_cb

    local request_feedback = function(start_time, srv, res, err)
        -- check whether need retry
        local end_time = now()
        local delta_time = end_time - start_time

        local feedback = retry_cb(res)
        set_status_cb(srv, feedback ~= REQUEST_SUCCESS) -- set some status
        if feedback ~= NEED_RETRY then
            return RETRY_DONE, res, err
        end

        local feedback_try_time = try_time_cb(delta_time)
        if feedback_try_time ~= NEED_RETRY then
            return RETRY_DONE, nil, "try_timeout excceed"
        end
        return NEED_RETRY
    end

    local default_itercls = function(cls, peer_cb, request_cb, request_feedback)
        for _, srv, opts, err in module.ipairsrvs(cls.servers, peer_cb, ups, opts) do
            if err then
                log(ERR, str_format("iter err: %s", err))
                return nil, err
            end
            local start_time = now()
            local res, err = request_cb(srv.host, srv.port, opts)
            local retry, res, err = request_feedback(start_time, srv, res, err)
            if retry == RETRY_DONE then
                return RETRY_DONE, res, err
            end
        end
    end

    local itercls = module.itercls or default_itercls

    local res, err = nil, "no servers available"
    repeat
        -- get next level/key cluster
        local cls = next_cluster_cb()
        if not cls then
            break
        end
        local retry, res, err = itercls(cls, peer_cb, request_cb, request_feedback)
        if retry == RETRY_DONE then
            return res, err
        end
    until false

    return res, err
end


return _M
