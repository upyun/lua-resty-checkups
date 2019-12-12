-- Copyright (C) 2014-2016, UPYUN Inc.

local floor      = math.floor
local str_byte   = string.byte
local tab_sort   = table.sort
local tab_insert = table.insert
local ipairs     = ipairs
local type       = type

local _M = { _VERSION = "0.11" }

local MOD       = 2 ^ 32
local REPLICAS  = 20
local LUCKY_NUM = 13


local function hash_string(str)
    local key = 0
    for i = 1, #str do
        key = (key * 31 + str_byte(str, i)) % MOD
    end

    return key
end


local function init_state(servers)
    local weight_sum = 0
    for _, srv in ipairs(servers) do
        weight_sum = weight_sum + (srv.weight or 1)
    end

    local circle, members = {}, 0
    for index, srv in ipairs(servers) do
        local key = ("%s:%s"):format(srv.host, srv.port)
        local base_hash = hash_string(key)
        for c = 1, REPLICAS * weight_sum do
            -- TODO: more balance hash
            local hash = (base_hash * c * LUCKY_NUM) % MOD
            tab_insert(circle, { hash, index })
        end
        members = members + 1
    end

    tab_sort(circle, function(a, b) return a[1] < b[1] end)

    return { circle = circle, members = members }
end


local function binary_search(circle, key)
    local size = #circle
    local st, ed, mid = 1, size
    while st <= ed do
        mid = floor((st + ed) / 2)
        if circle[mid][1] < key then
            st = mid + 1
        else
            ed = mid - 1
        end
    end

    return st == size + 1 and 1 or st
end


local function next_server(servers, peer_cb, opts)
    servers.chash = type(servers.chash) == "table" and servers.chash
                    or init_state(servers)

    local chash = servers.chash
    if chash.members == 1 then
        if peer_cb(1, servers[1]) then
            return 1, servers[1]
        end

        return nil, nil, nil, "consistent hash: no servers available"
    end

    local circle = chash.circle
    local st = binary_search(circle, hash_string(opts.hash_key))
    local size = #circle
    local ed = st + size - 1
    for i = st, ed do  -- TODO: algorithm O(n)
        local idx = circle[(i - 1) % size + 1][2]
        if peer_cb(idx, servers[idx]) then
            return idx, servers[idx]
        end
    end

    return nil, nil, nil, "consistent hash: no servers available"
end


local function gen_opts(ups, opts, skey)
    local key
    local mode = ups.mode
    if mode == "hash" then
        key = opts.hash_key or ngx.var.uri
    elseif mode == "url_hash" then
        key = ngx.var.uri
    elseif mode == "ip_hash" then
        key = ngx.var.remote_addr
    elseif mode == "header_hash" then
        key = ngx.var.http_x_hash_key or ngx.var.uri
    end
    return { hash_key=key }
end

function _M.ipairsrvs(servers, peer_cb, ups, opts, skey)
    local mopts = gen_opts(ups, opts, skey)
    return function() return next_server(servers, peer_cb, mopts) end
end


return _M
