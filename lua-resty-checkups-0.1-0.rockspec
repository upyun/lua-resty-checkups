package = 'lua-resty-checkups'
version = '0.1-0'
source = {
    url = "git://github.com/upyun/lua-resty-checkups",
    tag = "v0.1",
}

description = {
    summary = "Manage Nginx upstreams in pure ngx_lua",
    detailed = "Manage Nginx upstreams in pure ngx_lua",
    license = "2-clause BSD",
    homepage = "https://github.com/upyun/lua-resty-checkups",
    maintainer = "huangnauh (https://github.com/huangnauh)",
}

dependencies = {
    'lua >= 5.1',
}

build = {
    type = "builtin",
    modules = {
        ["resty.checkups"] = "lib/resty/checkups.lua",
        ["resty.subsystem"] = "lib/resty/subsystem.lua",
        ["resty.checkups.api"] = "lib/resty/checkups/api.lua",
        ["resty.checkups.base"] = "lib/resty/checkups/base.lua",
        ["resty.checkups.consistent_hash"] = "lib/resty/checkups/consistent_hash.lua",
        ["resty.checkups.dyconfig"] = "lib/resty/checkups/dyconfig.lua",
        ["resty.checkups.heartbeat"] = "lib/resty/checkups/heartbeat.lua",
        ["resty.checkups.round_robin"] = "lib/resty/checkups/round_robin.lua",
        ["resty.checkups.try"] = "lib/resty/checkups/try.lua",
    }
}
