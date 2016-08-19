
_M = {}

_M.global = {
    checkup_timer_interval = 5,
    checkup_timer_overtime = 10,
    checkup_shd_sync_enable = true,
    shd_config_timer_interval = 0.5,
}

_M.ups1 = {
    timeout = 2,
    try = 2,

    cluster = {
        {   -- level 1
            servers = {
            }
        },
        {   -- level 2
            servers = {
            }
        },
    },
}

_M.ups2 = {
    timeout = 2,
    try = 2,

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12350 },
            }
        },
        {   -- level 2
            servers = {
            }
        },
    },
}

_M.ups3 = {
    timeout = 2,
    try = 2,

    cluster = {
        {   -- level 1
            upstream = "api.com",
        },
        {   -- level 2
            upstream = "api.com",
            upstream_only_backup = true,
        },
    },
}

return _M
