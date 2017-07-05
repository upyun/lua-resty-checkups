# vim:set ft= ts=4 sw=4 et:

use lib 'lib';
use Test::Nginx::Socket;
use Cwd qw(cwd);
use Test::Nginx::Socket 'no_plan';

workers(1);
master_process_enabled(1);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_socket_log_errors off;
    lua_package_path "$pwd/../lua-resty-lock/?.lua;$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    error_log logs/error.log debug;

    lua_shared_dict state 10m;
    lua_shared_dict mutex 1m;
    lua_shared_dict locks 1m;
    lua_shared_dict config 10m;

    server {
        listen 12350;
        return 200 12350;
    }

    server {
        listen 12351;
        return 200 12351;
    }

    server {
        listen 12352;
        return 200 12352;
    }

    server {
        listen 12353;
        return 200 12353;
    }

    upstream api.com {
        server 127.0.0.1:12350;
        server 127.0.0.1:12351;
        server 127.0.0.1:12352 backup;
        server 127.0.0.1:12353 backup;
    }

    init_by_lua '
        local config = require "config_dyconfig"
        local checkups = require "resty.checkups"
        checkups.init(config)
    ';

    init_worker_by_lua '
        local config = require "config_dyconfig"
        local checkups = require "resty.checkups"
        checkups.prepare_checker(config)
        checkups.create_checker()
    ';
};


$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_CHECK_LEAK} = 1;
$ENV{TEST_NGINX_USE_HUP} = 1;
$ENV{TEST_NGINX_PWD} = $pwd;

#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: Add server
--- http_config eval: $::HttpConfig
--- config
    location = /12350 {
        proxy_pass http://127.0.0.1:12350/;
    }
    location = /12351 {
        proxy_pass http://127.0.0.1:12351/;
    }
    location = /12352 {
        proxy_pass http://127.0.0.1:12352/;
    }
    location = /12353 {
        proxy_pass http://127.0.0.1:12353/;
    }

    location = /t {
        content_by_lua '
            local checkups = require "resty.checkups"

            local callback = function(host, port)
                local res = ngx.location.capture("/" .. port)
                ngx.say(res.body)
                return 1
            end

            local ok, err

            -- no upstream available
            ok, err = checkups.ready_ok("ups1", callback)
            if err then ngx.say(err) end

            -- add server to backup level
            ok, err = checkups.update_upstream("ups1", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12353},
                        }
                    },
                })
            if err then ngx.say(err) end
            ngx.sleep(2)
            local pid = ngx.worker.pid()
            os.execute("kill " .. pid)
        ';
    }

    location = /tt {
        content_by_lua '
            ngx.sleep(2)
            local checkups = require "resty.checkups"

            local callback = function(host, port)
                local res = ngx.location.capture("/" .. port)
                ngx.say(res.body)
                return 1
            end

            local ok, err
            ok, err = checkups.ready_ok("ups1", callback)
            if err then ngx.say(err) end
        ';
    }
--- request eval
["GET /t", "GET /tt"]
--- response_body eval
["no servers available\n", "12353\n"]

--- timeout: 10
