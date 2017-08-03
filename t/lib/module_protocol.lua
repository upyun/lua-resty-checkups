local tcp           = ngx.socket.tcp
local _M = {}
local mt = { __index = _M }
local STATE_CONNECTED       = 1

function _M.new(self, config)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end

    return setmetatable({ _sock = sock, config=config}, mt)
end

function _M.settimeout(self, timeout)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end

function _M.setkeepalive(self, ...)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    if self.state ~= STATE_CONNECTED then
        return nil, "cannot be reused in the current connection state: "
                    .. self.state
    end

    self.state = nil

    local ok, err = sock:setkeepalive(...)
    return ok, err
end


function _M.connect(self, host, port)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    local ok, err = sock:connect(host, port)
    if not ok then
        return nil, 'failed to connect: ' .. err
    end

    local reused = sock:getreusedtimes()
    if reused and reused > 0 then
        self.state = STATE_CONNECTED
        return reused
    end
    local protocol_opts = rawget(self, "config") or {}
    local hello = protocol_opts.hello or "connected"
    local hello_len = string.len(hello)

    local bytes, err = sock:send(string.format("*3\r\n$3\r\nSET\r\n$5\r\nhello\r\n$%s\r\n%s\r\n", hello_len, hello))
    if not bytes then
        return nil, err
    end

    local data, err = sock:receive(5)
    if not data then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    elseif data ~= "+OK\r\n" then
        return nil, "send failed"
    end

    self.state = STATE_CONNECTED
    return reused or 0
end

function _M.hello(self)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    local bytes, err = sock:send("*2\r\n$3\r\nGET\r\n$5\r\nhello\r\n")
    if not bytes then
        return nil, err
    end

    local data, err = sock:receive()
    if not data then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end
    local len = tonumber(string.sub(data,2))
    if len <= 0 then
        return nil, "get failed"
    end

    local data, err = sock:receive(len)
    if not data then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end
    return data
end


function _M.close(self)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    self.state = nil

    local bytes, err = sock:send("*2\r\n$3\r\nDEL\r\n$5\r\nhello\r\n")
    if not bytes then
        return nil, err
    end

    local data, err = sock:receive(4)
    if not data then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    elseif data ~= ":1\r\n" then
        return nil, "send failed"
    end

    return sock:close()
end

return _M
