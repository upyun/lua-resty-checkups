# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
#use Test::Nginx::Socket;
use Cwd qw(cwd);
use Test::Nginx::Socket 'no_plan';

repeat_each(1);
master_on();

workers(16);

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
        listen 12356;
        location = /status {
            return 200;
        }
    }

    upstream api.com {
        server 127.0.0.1:12355;
        server 127.0.0.1:12356;
    }

    init_worker_by_lua '
        local config = require "config_down"
        local checkups = require "resty.checkups"
        checkups.prepare_checker(config)
        checkups.create_checker()
    ';

};

$ENV{TEST_NGINX_CHECK_LEAK} = 1;
$ENV{TEST_NGINX_USE_HUP} = 1;
$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
no_long_string();
no_diff();

run_tests();

__DATA__

=== TEST 1: set upstream down
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local upstream = require "ngx.upstream"

            ngx.sleep(1)
            local srvs = upstream.get_primary_peers("api.com")

            ngx.say(srvs[1].down)
            ngx.say(srvs[2].down)
        ';
    }
--- request eval
[
    "GET /t", 
    "GET /t",
    "GET /t",
    "GET /t",
    "GET /t",
    "GET /t",
    "GET /t",
    "GET /t",
    "GET /t",
    "GET /t",
]
--- response_body eval
[
    "true\nnil\n", 
    "true\nnil\n", 
    "true\nnil\n", 
    "true\nnil\n", 
    "true\nnil\n", 
    "true\nnil\n", 
    "true\nnil\n", 
    "true\nnil\n", 
    "true\nnil\n", 
    "true\nnil\n", 
]
--- timeout: 20


