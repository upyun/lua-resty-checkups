-- Copyright (C) 2016-2018 Libo Huang (huangnauh), UPYUN Inc.

local resolver  = require "resty.dns.resolver"
local dyconfig  = require "resty.checkups.dyconfig"
local base      = require "resty.checkups.base"

local ipairs    = ipairs
local pairs     = pairs
local next      = next
local type      = type
local concat    = table.concat
local log       = ngx.log
local ERR       = ngx.ERR
local WARN      = ngx.WARN
local timer_at  = ngx.timer.at
local spawn     = ngx.thread.spawn
local wait      = ngx.thread.wait


local _M = {}
local dns_config_getter

local function update_ips(domain_diff, domain_map)
    local lock, err = base.get_lock(base.SKEYS_KEY)
    if not lock then
        log(WARN, "failed to acquire the lock: ", err)
        return false
    end

    local dyupstreams = dyconfig.do_get_upstreams()
    for skey, ups in pairs(dyupstreams) do
        local should_update_cluster = false
        for level, cls in pairs(ups.cluster) do
            local domain_server_map = {}   --servers should update
            local should_update_servers = false
            for key, srv in ipairs(cls.servers) do
                -- need dns resolve
                if ups.dns or srv.dns then
                    if srv.domain then
                        -- domain already resolved
                        if domain_diff[srv.domain] then
                            if not domain_server_map[srv.domain] then
                                should_update_servers = true
                                domain_server_map[srv.domain] = srv
                            end
                            cls.servers[key] = nil
                        end
                    else
                        if domain_map[srv.host] and not domain_server_map[srv.host] then
                            -- new domain
                            should_update_servers = true
                            domain_server_map[srv.host] = srv
                            cls.servers[key] = nil
                        end
                    end
                end
            end
            
            if should_update_servers then
                local new_servers = {}
                local index = 1

                -- domain related server
                for domain, srv in pairs(domain_server_map) do
                    for _, ip in ipairs(domain_map[domain]) do
                        local new_server = base.table_dup(srv)
                        new_server.host = ip
                        new_server.domain = domain
                        new_servers[index] = new_server
                        index = index + 1
                    end
                end

                -- independent server
                for _, srv in pairs(cls.servers) do
                    new_servers[index] = srv
                    index = index + 1
                end

                cls.servers = new_servers

                should_update_cluster = true
            end
        end

        if should_update_cluster then
            dyconfig.do_update_upstream(skey, ups)
        end
    end

    base.release_lock(lock)
    return true
end



local function get_domains()
    local domains = {}
    for skey, ups in pairs(base.upstream.checkups) do
        for level, cls in pairs(ups.cluster) do
            for _, srv in ipairs(cls.servers) do
                -- need dns resolve
                if ups.dns or srv.dns then
                    domains[srv.domain or srv.host] = true
                end
            end
        end
    end
    return domains
end

local function query(domain, dns)
    local nameservers = dns.nameservers
    if type(nameservers) ~= "table" or #nameservers == 0 then
        return
    end

    local retrans = dns.retrans or 5
    local timeout = (dns.timeout or 2) * 1000
    local r, err = resolver:new{
        nameservers = nameservers,
        retrans = retrans,
        timeout = timeout,
    }
    if not r then
        log(ERR, "failed to instantiate the resolver: ", err)
        return
    end

    local answers, err, tries = r:query(domain, nil, {})
    if not answers then
        log(ERR, "failed to query the DNS server: ", err)
        log(ERR, "retry historie:  ", concat(tries, ":"))
        return
    end

    if answers.errcode then
        log(ERR, "server returned error code: ", answers.errcode, ": ", answers.errstr)
        return
    end

    local ret = {}
    for i, ans in ipairs(answers) do
        if type(ans.address) == "string" and #ans.address > 0 then
            ret[#ret + 1] = ans.address
        end
    end

    if next(ret) then
        return {domain = domain, ips = ret}
    end
end

local pre_domain_map = {}

local function get_domain_diff(pre_domain_map, domain_map)
    local domain_diff = {}
    for domain, ips in pairs(domain_map) do
        local pre_ips = pre_domain_map[domain]
        if not pre_ips or #ips ~= #pre_ips then
            domain_diff[domain] = true
        else
            table.sort(ips)
            table.sort(pre_ips)
            for index, ip in ipairs(ips) do
                if ip ~= pre_ips[index] then
                    domain_diff[domain] = true
                    break
                end
            end
        end
    end
    return domain_diff
end

local function resolver_timer(premature)
    if premature then
        return
    end

    local dns = dns_config_getter()
    local domains = get_domains()
    local interval = dns.interval or 30

    local thread = {}
    for domain in pairs(domains) do
        thread[#thread + 1] = spawn(query, domain, dns)
    end

    local domain_map = {}
    for _, v in ipairs(thread) do
        if v then
            local ret, data = wait(v)
            if ret and data ~= nil then
                domain_map[data.domain] = data.ips
            end
        end
    end

    local domain_diff = get_domain_diff(pre_domain_map, domain_map)
    if update_ips(domain_diff, domain_map) then
        pre_domain_map = domain_map
    end

    local ok, err = timer_at(interval, resolver_timer)
    if not ok then
        log(WARN, "failed to create resolver_timer: ", err)
    end
end

function _M.create_timer(dns_config_getter)
    dns_config_getter = dns_config_getter

    local ok, err = timer_at(0, resolver_timer)
    if not ok then
        log(ERR, "failed to create resolver_timer: ", err)
    end
end



return _M
