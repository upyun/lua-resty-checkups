
_M = {}

_M.global = {
    checkup_timer_interval = 200,
    checkup_timer_overtime = 10,
}


_M.amount = {
    try = 6,
    http_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
        statuses = {
            [502] = false,
        },
    },

    cluster = {
        {       
            servers = {
                { host = "127.0.0.1", port = 12358 },
                { host = "127.0.0.1", port = 12359 },
                { host = "127.0.0.1", port = 12360 },
                { host = "127.0.0.1", port = 12361 },
            }
        },
    },
}


_M.amount_ups = {
    try = 6,
    try_timeout = 4.1,
    http_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
        statuses = {
            [502] = false,
        },
    },

    cluster = {
        {
            servers = {
                { host = "127.0.0.1", port = 12358 },
                { host = "127.0.0.1", port = 12359 },
                { host = "127.0.0.1", port = 12360 },
                { host = "127.0.0.1", port = 12361 },
            }
        },
    },
}


return _M

