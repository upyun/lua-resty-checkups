# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;
use Cwd qw(cwd);
use Test::Nginx::Socket 'no_plan';

#repeat_each(2);

workers(4);

my $pwd = cwd();

our $HttpConfig1 = qq{
    lua_socket_log_errors off;
    lua_package_path "$pwd/../lua-resty-lock/?.lua;$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    error_log logs/error1.log debug;
    access_log logs/access1.log;

    lua_shared_dict state 10m;
    lua_shared_dict mutex 1m;
    lua_shared_dict locks 1m;

    server { listen 12358; location = /status {
            content_by_lua ' ngx.sleep(2); ngx.exit(502) '; } }

    server { listen 12359; location = /status {
            content_by_lua ' ngx.sleep(2); ngx.exit(502) '; } }

    server { listen 12360; location = /status {
            content_by_lua ' ngx.sleep(1); ngx.exit(502) '; } }

    server { listen 12361; location = /status {
            content_by_lua ' ngx.sleep(1); ngx.exit(200) '; } }

    init_by_lua '
        local config = require "config_timeout"
        local checkups = require "resty.checkups"
        checkups.prepare_checker(config)
    ';

};


$ENV{TEST_NGINX_CHECK_LEAK} = 1;
$ENV{TEST_NGINX_USE_HUP} = 1;
$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
#no_diff();
no_long_string();

run_tests();

__DATA__


=== TEST 1: try_timeout in ups
--- http_config eval: $::HttpConfig1
--- config
    location = /t {
        access_log logs/access11.log;
        error_log  logs/error11.log debug;
        content_by_lua_block {
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(3)

            local cb_ok = function(host, port)
                local sock = ngx.socket.tcp()
                sock:settimeout(10000)
                local ok, err = sock:connect(host, port)
                h = host
                p = port
                local bytes, err = sock:send("GET /status HTTP/1.0\r\n\r\n")
                local data, err, partial = sock:receive()
                if data == "HTTP/1.1 200 OK" then
                    return 1
                end
                return
            end

            local ok, err = checkups.ready_ok("amount_ups", cb_ok)
            if not ok then
                ngx.say("type ok: ", type(ok), " ", h, " ", p, " ", "err: ", err)
            else
                ngx.say("ok", " port: ", p, " host: ", h)
            end
        }

    }
--- request
GET /t
--- response_body
type ok: nil 127.0.0.1 12360 err: try_timeout excceed
--- timeout: 20



=== TEST 2: try_timeout in opts
--- http_config eval: $::HttpConfig1
--- config
    location = /t {
        access_log logs/access22.log;
        error_log  logs/error22.log debug;
        content_by_lua_block {
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(3)

            local h, p
            local cb_ok = function(host, port)
                local sock = ngx.socket.tcp()
                sock:settimeout(10000)
                local ok, err = sock:connect(host, port)
                h = host
                p = port
                local bytes, err = sock:send("GET /status HTTP/1.0\r\n\r\n")
                local data, err, partial = sock:receive()
                if data == "HTTP/1.1 200 OK" then
                    return 1
                end
                return
            end

            local ok, err = checkups.ready_ok("amount", cb_ok, {try_timeout = 4.1})
            if not ok then
                ngx.say("type ok: ", type(ok), " ", h, " ", p, " ", "err: ", err)
            else
                ngx.say("ok", " port: ", p, " host: ", h)
            end
        }

    }
--- request
GET /t
--- response_body
type ok: nil 127.0.0.1 12360 err: try_timeout excceed
--- timeout: 20


=== TEST 3: try_timeout = 0
--- http_config eval: $::HttpConfig1
--- config
    location = /t {
        access_log logs/access33.log;
        error_log  logs/error33.log debug;
        content_by_lua_block {
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(3)

            local h, p
            local cb_ok = function(host, port)
                local sock = ngx.socket.tcp()
                sock:settimeout(10000)
                local ok, err = sock:connect(host, port)
                h = host
                p = port
                local bytes, err = sock:send("GET /status HTTP/1.0\r\n\r\n")
                local data, err, partial = sock:receive()
                if data == "HTTP/1.1 200 OK" then
                    return 1
                end
                return
            end

            local ok, err = checkups.ready_ok("amount", cb_ok, {try_timeout = 0})
            if not ok then
                ngx.say("type ok: ", type(ok), " ", h, " ", p, " ", "err: ", err)
            else
                ngx.say("ok", " port: ", p, " host: ", h)
            end
        }

    }
--- request
GET /t
--- response_body
ok port: 12361 host: 127.0.0.1
--- timeout: 20

