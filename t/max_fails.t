# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;
use Cwd qw(cwd);
use Test::Nginx::Socket 'no_plan';

#repeat_each(2);

workers(1);

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
        listen 12355;
        listen 12356;
        location /b {
            lua_need_request_body on;
            content_by_lua '
                local args = ngx.req.get_uri_args()
                if args then
                    ngx.status = args.code
                    ngx.print(args.host .. ":" .. args.port .. ":" .. args.code)
                end
            ';
        }
    }

    init_by_lua '
        local config = require "config_fails"
        local checkups = require "resty.checkups"
        checkups.init(config)
    ';

    init_worker_by_lua '
        local checkups = require "resty.checkups"
        local config = require "config_fails"
        checkups.prepare_checker(config)
        checkups.create_checker()
    ';

};

$ENV{TEST_NGINX_CHECK_LEAK} = 1;
$ENV{TEST_NGINX_USE_HUP} = 1;
$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: max_fails timeout
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"

            local res = checkups.ready_ok("s1", function(host, port)
                local r = ngx.location.capture("/a", { args = { host = host, port = port, code = 200 } })
                if r then ngx.say(r.body) else ngx.say("ERR") end
                return r
            end)

            for i=1, 10 do
                local res = checkups.ready_ok("s1", function(host, port)
                    local r = ngx.location.capture("/a", { args = { host = host, port = port, code = 502 } })
                    if r then ngx.say(r.body) else ngx.say("ERR") end
                    return r
                end)
            end

            ngx.sleep(2.5)

            for i=1, 10 do
                local res = checkups.ready_ok("s1", function(host, port)
                    local r = ngx.location.capture("/a", { args = { host = host, port = port, code = 502 } })
                    if r then ngx.say(r.body) else ngx.say("ERR") end
                    return r
                end)
            end
        ';
    }
    location /a {
        proxy_pass http://127.0.0.1:$arg_port/b?code=$arg_code&host=$arg_host&port=$arg_port;
    }
--- request
GET /t
--- response_body
127.0.0.1:12354:200
127.0.0.1:12355:502
127.0.0.1:12354:502
127.0.0.1:12355:502
127.0.0.1:12354:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12354:502
127.0.0.1:12355:502
127.0.0.1:12354:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
--- timeout: 10


=== TEST 2: the last server will not be marked down
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"

            for i=1, 5 do
                local res = checkups.ready_ok("s2", function(host, port)
                    local r = ngx.location.capture("/a", { args = { host = host, port = port, code = 502 } })
                    if r then ngx.say(r.body) else ngx.say("ERR") end
                    return r
                end)
            end

            ngx.sleep(2.5)

            for i=1, 5 do
                local res = checkups.ready_ok("s2", function(host, port)
                    local r = ngx.location.capture("/a", { args = { host = host, port = port, code = 502 } })
                    if r then ngx.say(r.body) else ngx.say("ERR") end
                    return r
                end)
            end
        ';
    }
    location /a {
        proxy_pass http://127.0.0.1:$arg_port/b?code=$arg_code&host=$arg_host&port=$arg_port;
    }
--- request
GET /t
--- response_body
127.0.0.1:12354:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12354:502
127.0.0.1:12355:502
127.0.0.1:12355:502
127.0.0.1:12355:502
--- timeout: 10


=== TEST 3: backup server
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"

            for i=1, 5 do
                local res = checkups.ready_ok("s3", function(host, port)
                    local r = ngx.location.capture("/a", { args = { host = host, port = port, code = 502 } })
                    if r then ngx.say(r.body) else ngx.say("ERR") end
                    return r
                end)
            end

            ngx.sleep(2.5)

            for i=1, 5 do
                local res = checkups.ready_ok("s3", function(host, port)
                    local r = ngx.location.capture("/a", { args = { host = host, port = port, code = 502 } })
                    if r then ngx.say(r.body) else ngx.say("ERR") end
                    return r
                end)
            end
        ';
    }
    location /a {
        proxy_pass http://127.0.0.1:$arg_port/b?code=$arg_code&host=$arg_host&port=$arg_port;
    }
--- request
GET /t
--- response_body
127.0.0.1:12354:502
127.0.0.1:12355:502
127.0.0.1:12356:502
127.0.0.1:12356:502
127.0.0.1:12356:502
127.0.0.1:12355:502
127.0.0.1:12354:502
127.0.0.1:12356:502
127.0.0.1:12356:502
127.0.0.1:12356:502
--- timeout: 10
