-- Copyright (C) 2014-2016, UPYUN Inc.

local cjson           = require "cjson.safe"
local round_robin     = require "resty.checkups.round_robin"
local consistent_hash = require "resty.checkups.consistent_hash"

local max        = math.max
local sqrt       = math.sqrt
local floor      = math.floor
local tab_insert = table.insert

local state = ngx.shared.state

local _M = { _VERSION = "0.11" }

local NEED_RETRY       = 0
local REQUEST_SUCCESS  = 1
local EXCESS_TRY_LIMIT = 2


local function prepare_callbacks(skey, opts)
    local base = require "resty.checkups.base"
    local is_tab = base.is_tab
    local ups = base.upstream.checkups[skey]

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


    -- get next select server
    local mode = ups.mode
    local key = opts.hash_key or ngx.var.uri
    local next_server_func = round_robin.next_round_robin_server
    if mode == "hash" then
        next_server_func = consistent_hash.next_consistent_hash_server
    end
    local next_server_cb = function(servers, peer_cb)
        return next_server_func(servers, peer_cb, key)
    end


    -- check whether ther server is available
    local bad_servers = {}
    local peer_cb = function(index, srv)
        local key = ("%s:%s:%s"):format(cls_key, srv.host, srv.port)
        if bad_servers[key] then
            return false
        end

        local peer_status = base.get_peer_status(skey, srv)
        if (not peer_status or peer_status.status ~= base.STATUS_ERR)
        and base.get_srv_status(skey, srv) == base.STATUS_OK then
            return true
        end
    end


    -- check whether need retry
    local statuses
    if ups.typ == "http" and is_tab(ups.http_opts) then
        statuses = ups.http_opts.statuses
    end
    local try_cnt = 0
    local try_limit = opts.try or ups.try or srvs_cnt
    local retry_cb = function(res, err)
        if is_tab(res) and res.status and is_tab(statuses) then
            if statuses[res.status] ~= false then
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


    -- set some status
    local free_server_func = round_robin.free_round_robin_server
    if mode == "hash" then
        free_server_func = consistent_hash.free_consitent_hash_server
    end
    local set_status_cb = function(srv, failed)
        local key = ("%s:%s:%s"):format(cls_key, srv.host, srv.port)
        bad_servers[key] = failed
        base.set_srv_status(skey, srv, failed)
        free_server_func(srv, failed)
    end


    return {
        next_cluster_cb = next_cluster_cb,
        next_server_cb = next_server_cb,
        retry_cb = retry_cb,
        peer_cb = peer_cb,
        set_status_cb = set_status_cb,
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
    local callbacks = prepare_callbacks(skey, opts)

    local next_cluster_cb = callbacks.next_cluster_cb
    local next_server_cb  = callbacks.next_server_cb
    local peer_cb         = callbacks.peer_cb
    local retry_cb        = callbacks.retry_cb
    local set_status_cb   = callbacks.set_status_cb

    -- iter servers function
    local itersrvs = function(servers, peer_cb)
        return function() return next_server_cb(servers, peer_cb) end
    end

    local res, err = nil, "no servers available"
    repeat
        -- get next level/key cluster
        local cls = next_cluster_cb()
        if not cls then
            break
        end

        for srv, err in itersrvs(cls.servers, peer_cb) do
            -- exec request callback by server
            res, err = request_cb(srv.host, srv.port)

            -- check whether need retry
            local feedback = retry_cb(res, err)
            set_status_cb(srv, feedback ~= REQUEST_SUCCESS) -- set some status
            if feedback ~= NEED_RETRY then
                return res, err
            end
        end
    until false

    return res, err
end


return _M
