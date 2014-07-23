# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;
use Cwd qw(cwd);

#repeat_each(2);

workers(4);

use Test::Nginx::Socket 'no_plan';
#plan tests => repeat_each() * (blocks() * 2 + 2);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_socket_log_errors off;
    lua_package_path "$pwd/../lua-resty-lock/?.lua;$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    error_log logs/error.log debug;

    lua_shared_dict state 10m;
    lua_shared_dict mutex 1m;
    lua_shared_dict locks 1m;

    server {
        listen 12354;
        location = /status {
            return 200;
        }
    }

    server {
        listen 12355;
        location = /status {
            return 404;
        }
    }

    server {
        listen 12360;
        location = /status {
            return 404;
        }
    }

    init_by_lua '
        local config = require "config_api"
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

=== TEST 1: check without passive
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(1)
            local cb_ok = function(host, port)
                ngx.say(host .. ":" .. port)
                return 1
            end
            local cb_err = function(host, port)
                ngx.say(host .. ":" .. port .. " " .. "ERR")
                return nil, "max try exceeded"
            end

            local ok, err = checkups.ready_ok("api", cb_err)
            if err then
                ngx.say(err)
            end
            local ok, err = checkups.ready_ok("api", cb_err)
            if err then
                ngx.say(err)
            end
            local ok, err = checkups.ready_ok("api", cb_ok)
            if err then
                ngx.say(err)
            end
            local ok, err = checkups.ready_ok("api", cb_ok)
            if err then
                ngx.say(err)
            end
        ';
    }
--- request
GET /t
--- response_body
127.0.0.1:12354 ERR
127.0.0.1:12355 ERR
max try exceeded
127.0.0.1:12355 ERR
127.0.0.1:12354 ERR
max try exceeded
127.0.0.1:12354
127.0.0.1:12354
--- grep_error_log eval: qr/cb_heartbeat\(\): failed to connect: 127.0.0.1:\d+ connection refused/
--- grep_error_log_out
cb_heartbeat(): failed to connect: 127.0.0.1:12356 connection refused
cb_heartbeat(): failed to connect: 127.0.0.1:12361 connection refused


=== TEST 2: check timer
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(3)
        ';
    }
--- request
GET /t
--- response_body
--- grep_error_log eval: qr/cb_heartbeat\(\): failed to connect: 127.0.0.1:\d+ connection refused/
--- grep_error_log_out
cb_heartbeat(): failed to connect: 127.0.0.1:12356 connection refused
cb_heartbeat(): failed to connect: 127.0.0.1:12361 connection refused
cb_heartbeat(): failed to connect: 127.0.0.1:12356 connection refused
cb_heartbeat(): failed to connect: 127.0.0.1:12361 connection refused
--- timeout: 10
