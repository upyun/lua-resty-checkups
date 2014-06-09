
_M = {}

_M.global = {
    positive_check = true,
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.api = {
    timeout = 2,
    typ = "general",
    max_acc_fails = 1,
    acc_timeout = 5,

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
