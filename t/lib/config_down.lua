
_M = {}

_M.global = {
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,

    ups_status_sync_enable = true,
    ups_status_timer_interval = 1,
}

_M.api = {
    timeout = 2,

    cluster = {
        {   -- level 1
            upstream = "api.com",
        },
    },
}

return _M
