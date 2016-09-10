
_M = {}

_M.global = {
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.status = {
    timeout = 5,
    typ = "http",
    try = 1,
    http_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
        statuses = {
            [502] = false,
        },
    },

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12354, max_fails = 1 },
                { host = "127.0.0.1", port = 12355 },
                { host = "127.0.0.1", port = 12356, max_fails = 1 },
                { host = "127.0.0.1", port = 12357 },
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
