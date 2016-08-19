_M = {}

_M.global = {
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.single_host = {
    cluster = {
        {
            servers = {
                { host = "127.0.0.1", port = 12350 },
            }
        }
    }
}

_M.single_level = {
    timeout = 2,

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12351, weight = 1 },
                { host = "127.0.0.1", port = 12352, weight = 4 },
                { host = "127.0.0.1", port = 12353, weight = 3 },
                { host = "127.0.0.1", port = 12355, weight = 6 },
            }
        },
    },
}

_M.multi_level = {
    timeout = 2,
    try = 8,

    cluster = {
        {   -- level 1
            servers = {
                { host = "127.0.0.1", port = 12354, weight = 2 }, -- fake
                { host = "127.0.0.1", port = 12355, weight = 3 },
                { host = "127.0.0.1", port = 12356, weight = 2 },
            }
        },
        {   -- level 2
            servers = {
                { host = "127.0.0.1", port = 12357, weight = 3 }, -- fake
                { host = "127.0.0.1", port = 12358, weight = 2 },
                { host = "127.0.0.1", port = 12359, weight = 2 }, -- fake
            }
        },
    },
}

_M.single_key = {
    timeout = 2,

    cluster = {
        c1 = {
            servers = {
                { host = "127.0.0.1", port = 12351, weight = 1 },
                { host = "127.0.0.1", port = 12352, weight = 2 },
                { host = "127.0.0.1", port = 12353, weight = 3 },
            }
        },
    },
}

_M.multi_key = {
    timeout = 2,
    try = 6,

    cluster = {
        c1 = {
            servers = {
                { host = "127.0.0.1", port = 12354, weight = 2 }, -- fake
                { host = "127.0.0.1", port = 12355, weight = 3 },
                { host = "127.0.0.1", port = 12356, weight = 2 },
            }
        },

        c2 = {
            servers = {
                { host = "127.0.0.1", port = 12357, weight = 3 }, -- fake
                { host = "127.0.0.1", port = 12358, weight = 1 },
                { host = "127.0.0.1", port = 12359, weight = 2 }, -- fake
            }
        },
    },
}


_M.multi_fake_c1 = {
    timeout = 2,
    try = 6,

    cluster = {
        c1 = {
            servers = {
                { host = "127.0.0.1", port = 12357, weight = 3000 },    -- fake
                { host = "127.0.0.1", port = 12359, weight = 3200000 }, -- fake
                { host = "127.0.0.1", port = 12356, weight = 1 },
            }
        },

        c2 = {
            servers = {
                { host = "127.0.0.1", port = 12357, weight = 3 }, -- fake
                { host = "127.0.0.1", port = 12358, weight = 1 },
                { host = "127.0.0.1", port = 12359, weight = 2 }, -- fake
            }
        },
    },
}


return _M
