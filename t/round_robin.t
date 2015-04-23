# vim:set ft= ts=4 sw=4 et:

use lib 'lib';
use Test::Nginx::Socket;
use Cwd qw(cwd);
use Test::Nginx::Socket 'no_plan';

workers(4);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_socket_log_errors off;
    lua_package_path "$pwd/../lua-resty-lock/?.lua;$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    error_log logs/error.log debug;

    lua_shared_dict state 10m;
    lua_shared_dict mutex 1m;
    lua_shared_dict locks 1m;
    lua_shared_dict ip_black_lists 10m;
    lua_shared_dict round_robin_state 10m;

    server {
        listen 12350;
    }

    server {
        listen 12351;
    }

    server {
        listen 12352;
    }

    server {
        listen 12353;
    }

    server {
        listen 12355;
    }

    server {
        listen 12356;
    }

    server {
        listen 12358;
    }
};

our $InitConfig = qq{
    init_by_lua '
        local config = require "config_round_robin"
        local checkups = require "resty.checkups"
        checkups.prepare_checker(config)
    ';
};


$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_CHECK_LEAK} = 1;
$ENV{TEST_NGINX_USE_HUP} = 1;

#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: Round robin method, single host
--- http_config eval
"$::HttpConfig" . "$::InitConfig"
--- config
    location = /t {
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(2)
            local cb_ok = function(host, port)
                ngx.say(host .. ":" .. port)
                return 1
            end

            local ok, err = checkups.ready_ok("single_host", cb_ok)
            if err then
                ngx.say(err)
            end
        ';
    }
--- request
GET /t
--- response_body
127.0.0.1:12350

=== TEST 2: Round robin is consistent, try by level
--- http_config eval
"$::HttpConfig" . "$::InitConfig"
--- config
    location = /t {
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(2)
            local dict = {
                [12351] = "A",
                [12352] = "B",
                [12353] = "C",
                [12355] = "E",
            }
            local cb_ok = function(host, port)
                ngx.print(dict[port])
                return 1
            end

            for i = 1, 30, 1 do
                local ok, err = checkups.ready_ok("single_level", cb_ok)
                if err then
                    ngx.say(err)
                end
            end
        ';
    }
--- request
GET /t
--- response_body: EEBEBCEBCEABCEEEBEBCEBCEABCEEE

=== TEST 3: Round robin with fake hosts, try by level
--- http_config eval
"$::HttpConfig" . "$::InitConfig"
--- config
    location = /t {
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(2)
            local dict = {
                [12355] = "E",
                [12356] = "F",
                [12358] = "H",
            }
            local cb_ok = function(host, port)
                ngx.print(dict[port])
                return
            end

            local ok, err = checkups.ready_ok("multi_level", cb_ok)
            if err then
                ngx.say(err)
            end
        ';
    }
--- request
GET /t
--- response_body
EEFHno upstream available

=== TEST 4: Round robin is consistent, try by key
--- http_config eval
"$::HttpConfig" . "$::InitConfig"
--- config
    location = /t {
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(2)
            local dict = {
                [12351] = "A",
                [12352] = "B",
                [12353] = "C",
            }
            local cb_ok = function(host, port)
                ngx.print(dict[port])
                return 1
            end

            for i = 1, 20, 1 do
                local ok, err = checkups.ready_ok("single_key", cb_ok, {cluster_key = {default = "c1"}})
                if err then
                    ngx.say(err)
                end
            end
        ';
    }
--- request
GET /t
--- response_body: CBCABCCBCABCCBCABCCB

=== TEST 5: Round robin with fake hosts, try by key
--- http_config eval
"$::HttpConfig" . "$::InitConfig"
--- config
    location = /t {
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(2)
            local dict = {
                [12355] = "E",
                [12356] = "F",
                [12358] = "H",
            }
            local cb_ok = function(host, port)
                ngx.print(dict[port])
                return
            end

            local ok, err = checkups.ready_ok("multi_key", cb_ok, {cluster_key = {default = "c1", backup = "c2"}})
            if err then
                ngx.say(err)
            end
        ';
    }
--- request
GET /t
--- response_body
EEFHHHno upstream available

=== TEST 6: Round robin with multiple fake hosts and large weight, try by key
--- http_config eval
"$::HttpConfig" . "$::InitConfig"
--- config
    location = /t {
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(2)
            local dict = {
                [12356] = "F",
                [12358] = "H",
            }
            local cb_ok = function(host, port)
                ngx.print(dict[port])
                return
            end

            local ok, err = checkups.ready_ok("multi_fake_c1", cb_ok, {cluster_key = {default = "c1", backup = "c2"}})
            if err then
                ngx.say(err)
            end
        ';
    }
--- request
GET /t
--- response_body
FFFHHHno upstream available

=== TEST 7: Round robin interface
--- http_config eval
"$::HttpConfig" . "$::InitConfig"
--- config
    location = /t {
        content_by_lua '
            local cjson    = require "cjson.safe"
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(2)

            local str_format = string.format

            local rr_state = ngx.shared.round_robin_state
            local ip_black_lists = ngx.shared.ip_black_lists

            local dict = { [12350] = "0",
                [12351] = "A",
                [12352] = "B",
                [12353] = "C",
                [12354] = "D",
                [12355] = "E",
                [12356] = "F",
                [12357] = "G",
            }

            local metadata = {
                ctn = {
                    servers = {
                       { host = "127.0.0.1", port = 12350, weight = 1 },
                       { host = "127.0.0.1", port = 12351, weight = 2 },
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
                       { host = "127.0.0.1", port = 12354, weight = 5 },
                       { host = "127.0.0.1", port = 12356, weight = 3 },
                    },
                },
            }

            local verify_server_status = function(srv)
                if ip_black_lists:get(str_format("%s:%s:%d", "bucket", srv.host, srv.port)) then
                    return false
                end

                return true
            end

            local callback = function(srv, ckey, state)
                rr_state:set("bucket:" .. ckey, cjson.encode(state), 5 * 60)

                local res
                if srv.port == 12354 or srv.port == 12357 then
                    res = { status = 502 }
                else
                    ngx.print(dict[srv.port])
                end

                if res and res.status == 502 then
                    ip_black_lists:set(str_format("%s:%s:%d", "bucket", srv.host, srv.port), 1, 10)
                    return nil, "bad status"
                end

                return res, " port: " .. srv.port
            end

            local update_rr_state = function(ckey, cls)
                local gcd, max_weight = checkups.calc_gcd_weight(cls.servers)
                local state = rr_state:get("bucket:" .. ckey)
                if state then
                    local rr, err = cjson.decode(state)
                    if rr then
                        rr.gcd, rr.max_weight = gcd, max_weight
                        cls.rr = rr
                    end
                end

                if not cls.rr then
                    cls.rr = { gcd = gcd, max_weight = max_weight, idx = 0, cw = 0 }
                end
            end

            local opts = { try = 20, cluster_key = {"ctn", "cun", "cmn"} }
            for i = 1, 5, 1 do
                local res, err = checkups.try_cluster_round_robin(metadata,
                    update_rr_state, verify_server_status, callback, opts)
                if err then
                    ngx.say(err)
                end
            end
            ngx.sleep(10)

            for i = 1, 5, 1 do
                local res, err = checkups.try_cluster_round_robin(metadata,
                    update_rr_state, verify_server_status, callback, opts)
                if err then
                    ngx.say(err)
                end
            end

            opts.try = 2
            for i = 1, 5, 1 do
                local res, err = checkups.try_cluster_round_robin(metadata,
                    update_rr_state, verify_server_status, callback, opts)
                if err then
                    ngx.say(err)
                end
            end
        ';
    }
--- request
GET /t
--- response_body
A0EFF port: 12356
AAEEFF port: 12356
0AEEFF port: 12356
A0EEFF port: 12356
AAEEFF port: 12356
0AEFF port: 12356
A0EEFF port: 12356
AAEEFF port: 12356
0AEEFF port: 12356
A0EEFF port: 12356
AA port: 12351
0A port: 12351
A0 port: 12350
AA port: 12351
0A port: 12351
--- timeout: 20
