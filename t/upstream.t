# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;
use Cwd qw(cwd);
use Test::Nginx::Socket 'no_plan';

#repeat_each(2);

workers(4);

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
            return 404;
        }
    }

    upstream api.com {
        server 127.0.0.1:12354;
        server 127.0.0.1:12355;
        server 127.0.0.1:12356 backup;
        server 127.0.0.1:12357 backup;
    }

    init_worker_by_lua '
        local checkups = require "resty.checkups"
        local config = require "config_ups"
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

=== TEST 1: set upstream down
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local upstream = require "ngx.upstream"
            local checkups = require "resty.checkups"

            local srvs = upstream.get_primary_peers("api.com")
            ngx.say(srvs[1].down)
            ngx.say(srvs[2].down)

            local srvs = upstream.get_backup_peers("api.com")
            ngx.say(srvs[1].down)
            ngx.say(srvs[2].down)

            ngx.sleep(2)

            local srvs = upstream.get_primary_peers("api.com")
            ngx.say(srvs[1].down)
            ngx.say(srvs[2].down)

            local srvs = upstream.get_backup_peers("api.com")
            ngx.say(srvs[1].down)
            ngx.say(srvs[2].down)
        ';
    }
--- request
GET /t
--- response_body
nil
nil
nil
nil
nil
true
nil
true
--- timeout: 10
