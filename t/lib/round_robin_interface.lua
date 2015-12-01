local cjson    = require "cjson.safe"
local checkups = require "resty.checkups"

local str_format = string.format

checkups.create_checker()
ngx.sleep(2)

local str_format = string.format

local RR_STATE_PREFIX = str_format("%s:%d", "rr", ngx.worker.pid())

local rr_state = ngx.shared.round_robin_state
local ip_black_lists = ngx.shared.ip_black_lists


local dict = {
    [12350] = "0", [12351] = "A", [12352] = "B",
    [12353] = "C", [12354] = "D", [12355] = "E",
    [12356] = "F", [12357] = "G", [12358] = "H",
}

local function gen_rr_key(bucket)
    return str_format("%s:%s", RR_STATE_PREFIX, bucket)
end

local function set_cdn_data(bucket)
    local key = gen_rr_key(bucket)
    local ok, err, forcible = rr_state:set(key, cjson.encode(ngx.ctx.cdn_data), 60 * 60)
    if not ok then
        ngx.log(ngx.WARN, "set_cdn_data: ", err)
    end

    if forcible then
        ngx.log(ngx.WARN, "set_cdn_data: romove other valid items")
    end
end

local function del_cdn_data(bucket)
    local key = gen_rr_key(bucket)
    local ok, err = rr_state:delete(key)
    if not ok then
        ngx.log(ngx.WARN, "del_cdn_data: ", err)
    end
end

local function get_cdn_data(bucket)
    local cdn_data
    local sh_key = gen_rr_key(bucket)
    local res, flags = rr_state:get(sh_key)
    if res then
        cdn_data = cjson.decode(res)
    end

    if not cdn_data or cdn_data.conf_hash ~= "Pv4I8sJRemLibLugEo" then
        -- get cdn_data from redis
        cdn_data = {
            ctn = {
                servers = {
                   { host = "127.0.0.1", port = 12350, weight = 4     },
                   { host = "127.0.0.1", port = 12351, weight = 2     },
                   { host = "127.0.0.1", port = 12357, weight = 20000 },
                },
            },
            cun = {
                servers = {
                   { host = "127.0.0.1", port = 12354, weight = 3 },
                   { host = "127.0.0.1", port = 12355, weight = 2 },
                },
            },
            cmn = {
                servers = {
                   { host = "127.0.0.1", port = 12351, weight = 2 },
                   { host = "127.0.0.1", port = 12354, weight = 5 },
                   { host = "127.0.0.1", port = 12356, weight = 3 },
                },
            },
        }

        cdn_data.conf_hash = "Pv4I8sJRemLibLugEo"
        for ckey, cls in pairs(cdn_data) do
            if type(cls) == "table" and type(cls.servers) == "table" and next(cls.servers) then
                checkups.reset_round_robin_state(cls)
            else
                cdn_data[ckey] = nil
            end
        end
    end

    return cdn_data
end

local verify_server_status = function(srv)
    if srv.port == 12356 then
        ngx.print(' ' .. srv.effective_weight .. ' ')
    end

    if ip_black_lists:get(str_format("%s:%s:%d", "bucket", srv.host, srv.port)) then
        return false
    end

    return true
end

local callback = function(srv, ckey)
    ngx.print(dict[srv.port])

    local res
    if srv.port == 12354 or srv.port == 12357 then
        res = { status = 502 }
    end

    if res and res.status == 502 then
        ip_black_lists:set(str_format("%s:%s:%d", "bucket", srv.host, srv.port), 1, 10)
        return nil, "bad status"
    end

    return res, " port: " .. srv.port
end

del_cdn_data("bucket")
ngx.ctx.cdn_data = get_cdn_data("bucket")
local opts = { cluster_key = {"ctn", "cun", "cmn"} }
for i = 1, 5, 1 do
    opts.try = 20
    local res, err = checkups.try_cluster_round_robin(ngx.ctx.cdn_data, verify_server_status, callback, opts)
    set_cdn_data("bucket")
    if err then
        ngx.print(' ')
        ngx.say(err)
    end
end
ngx.say('')
ngx.sleep(10)


del_cdn_data("bucket")
ngx.ctx.cdn_data = get_cdn_data("bucket")
for i = 1, 5, 1 do
    opts.try = 20
    local res, err = checkups.try_cluster_round_robin(ngx.ctx.cdn_data, verify_server_status, callback, opts)
    set_cdn_data("bucket")
    if err then
        ngx.print(' ')
        ngx.say(err)
    end
end
ngx.say('')


local _callback = function(srv, ckey)
    ngx.print(dict[srv.port])

    local res
    if srv.port == 12354 or srv.port == 12357 then
        res = { status = 502 }
    elseif srv.port == 12356 then
        res = { status = 200 }
    end

    if res and res.status == 502 then
        ip_black_lists:set(str_format("%s:%s:%d", "bucket", srv.host, srv.port), 1, 10)
        return nil, "bad status"
    end

    return res, " port: " .. srv.port
end

del_cdn_data("bucket")
ngx.ctx.cdn_data = get_cdn_data("bucket")
for i = 1, 5, 1 do
    opts.try = 20
    ngx.print(' ')
    local res, err
    if i < 3 then
        res, err = checkups.try_cluster_round_robin(ngx.ctx.cdn_data, verify_server_status, callback, opts)
    else
        res, err = checkups.try_cluster_round_robin(ngx.ctx.cdn_data, verify_server_status, _callback, opts)
    end

    set_cdn_data("bucket")
    if err then
        ngx.print(' ')
        ngx.say(err)
    end
end
ngx.say('')
ngx.say('')


del_cdn_data("bucket")
ngx.ctx.cdn_data = get_cdn_data("bucket")
for i = 1, 5, 1 do
    opts.try = 2
    local res, err = checkups.try_cluster_round_robin(ngx.ctx.cdn_data, verify_server_status, callback, opts)
    set_cdn_data("bucket")
    if err then
        ngx.say(err)
    end
end
ngx.say('')
ngx.sleep(10)


local callback = function(srv, ckey)
    local check_res = function(res, err)
        if res then
            if res.status == 200 then
                return true
            else
                return false, "bad status: " .. res.status
            end
        end

        return false, err or "no res"
    end

    local res = (function()
        if srv.port == 12354 or srv.port == 12357 then
            return { status = 502 }
        else
            return { status = 200, port = srv.port }
        end
    end)()

    local ok, err = check_res(res)
    if not ok then
        ip_black_lists:set(str_format("%s:%s:%d", "bucket", srv.host, srv.port), 1, 10)
        return nil, err
    end

    return res
end

del_cdn_data("bucket")
ngx.ctx.cdn_data = get_cdn_data("bucket")
local opts = { cluster_key = {"ctn", "cun", "cmn"} }
for i = 1, 20, 1 do
    opts.try = 5
    local res, err = checkups.try_cluster_round_robin(ngx.ctx.cdn_data, verify_server_status, callback, opts)
    set_cdn_data("bucket")
    if res then
        ngx.print(dict[res.port])
    end

    if err then
        ngx.say(err)
    end
end
ngx.say('|')

ngx.exit(ngx.HTTP_OK)
