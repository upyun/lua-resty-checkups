local _M = {}


_M.global = {
    checkup_timer_interval = 10,
    checkup_timer_overtime = 10,
}


_M.tcp_protocol = {
    timeout = 2,
    enable = true,

    -- TCP-based protocol
    protocol = {
        module = "module_protocol",
        config = {}
    },

    keepalive_size = 2,
    keepalive_timeout = 200,

    cluster = {
        {
            servers = {
                { host = "127.0.0.1", port = 6379 },
            },
        },
    },
}

return _M
