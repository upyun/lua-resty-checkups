
_M = {}

_M.global = {
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.redis = {
    enable = true,
    typ = "redis",

    cluster = {
        {
            servers = {
                { host = "127.0.0.1", port = 6379 },
            }
        }
    }
}


return _M
