
_M = {}

_M.global = {
    checkup_timer_interval = 5,
    checkup_timer_overtime = 10,
    checkup_shd_sync_enable = true,
    shd_config_timer_interval = 0.5,
}

_M.dyconfig_rr = {
    timeout = 2,
    typ = "http",
    try = 3,
    http_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
    },

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12355 },
                { host = "127.0.0.1", port = 12356 },
            }
        },
        {   -- level 2
            servers = {
                { host = "127.0.0.1", port = 12360 },
                { host = "127.0.0.1", port = 12361 },
            }
        },
    },
}

_M.dyconfig_hash = {
    timeout = 2,
    typ = "http",
    mode = "hash",
    try = 3,
    http_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
    },

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12354 },
                { host = "127.0.0.1", port = 12355 },
                { host = "127.0.0.1", port = 12356 },
            }
        },
        {   -- level 2
            servers = {
                { host = "127.0.0.1", port = 12360 },
                { host = "127.0.0.1", port = 12361 },
            }
        },
    },
}

return _M
