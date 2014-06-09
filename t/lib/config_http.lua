
_M = {}

_M.global = {
    positive_check = true,
    passive_check = true,
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.status = {
    timeout = 2,
    typ = "http",
    heartbeat_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
        statuses = {
            [200] = true,
            [404] = true,
            [502] = false,
        },
    },
    max_fails = 1,

    cluster = {
        {   -- level 1
            try = 2,
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
