
_M = {}

_M.global = {
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.s1 = {
    timeout = 2,
    typ = "http",
    try = 1,
    http_opts = {
        statuses = {
            [502] = false,
        },
    },

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12354, max_fails = 2, fail_timeout = 2 },
                { host = "127.0.0.1", port = 12355, max_fails = 0 },
            }
        },
        {   -- level 2
            servers = {
                { host = "127.0.0.1", port = 12356 },
            }
        },
    },
}

_M.s2 = {
    timeout = 2,
    typ = "http",
    try = 1,
    http_opts = {
        statuses = {
            [502] = false,
        },
    },

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12354, max_fails = 1, fail_timeout = 2 },
                { host = "127.0.0.1", port = 12355, max_fails = 1, fail_timeout = 2 },
            }
        },
    },
}

_M.s3 = {
    timeout = 2,
    typ = "http",
    try = 1,
    http_opts = {
        statuses = {
            [502] = false,
        },
    },

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12354, max_fails = 1, fail_timeout = 2 },
                { host = "127.0.0.1", port = 12355, max_fails = 1, fail_timeout = 2 },
            }
        },
        {   -- level 2
            servers = {
                { host = "127.0.0.1", port = 12356, max_fails = 1, fail_timeout = 2 },
            }
        },
    },
}

return _M
