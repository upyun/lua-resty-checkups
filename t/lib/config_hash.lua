
_M = {}

_M.global = {
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.hash = {
    timeout = 2,
    typ = "http",
    mode = "hash",
    http_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
        statuses = {
            [502] = false,
        },
    },

    cluster = {
        {   -- level 1
            try = 3,
            backup_node_count = 1,
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
