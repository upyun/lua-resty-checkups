
_M = {}

_M.global = {
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.upyun = {
    timeout = 2,
    typ = "http",
    http_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
        statuses = {
            [502] = false,
            [501] = false,
            [500] = false,
        },
    },

    cluster = {
        c1 = {
            try = 2,
            servers = {
                { host = "127.0.0.1", port = 12354 },
                { host = "127.0.0.1", port = 12355 },
                { host = "127.0.0.1", port = 12356 },
                { host = "127.0.0.1", port = 12357 },
            }
        },
        c2 = {
            servers = {
                { host = "127.0.0.1", port = 12355 },
                { host = "127.0.0.1", port = 12356 },
                { host = "127.0.0.1", port = 12357 },
                { host = "127.0.0.1", port = 12354 },
            }
        },
    },
}

return _M
