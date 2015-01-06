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

    init_by_lua '
        local config = require "config_redis"
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

=== TEST 1: redis replication info
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(1)

            local callback = function(host, port)
                ngx.say(host .. ":" .. port .. " " .. "OK")
            end
            checkups.ready_ok("redis", callback)

            local st = checkups.get_status()
            ngx.say(st["cls:redis"][1][1].status)
            ngx.say(st["cls:redis"][1][1].msg)
            ngx.say(st["cls:redis"][1][1].replication.role)

            ngx.sleep(2)
            local st = checkups.get_status()
            ngx.say(st["cls:redis"][1][1].status)
            ngx.say(st["cls:redis"][1][1].msg)
            ngx.say(st["cls:redis"][1][1].replication.role)
        ';
    }
--- request
GET /t
--- response_body_like
127.0.0.1:6379 OK
ok
null
master|slave
0
ok
null
master|slave
0
--- timeout: 10
