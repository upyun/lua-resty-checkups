local _M = {}


_M.global = {
    checkup_timer_interval = 10,
    checkup_timer_overtime = 10,
}


_M.tcp_protocol = {
    timeout = 2,
    typ = "tcp_protocol",
    enable = true,

    -- TCP-based protocol
    protocol = {
        module = "module_protocol",
        config = {hello="magic identifier"}
    },

    keepalive_size = 1,
    keepalive_timeout = 0,

    cluster = {
        {
            servers = {
                { host = "127.0.0.1", port = 6379 },
            },
        },
    },
}

return _M
