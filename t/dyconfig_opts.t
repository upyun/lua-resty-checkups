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
    lua_shared_dict config 10m;

    server {
        listen 12354;
        location = /status {
            return 200;
        }
    }

    server {
        listen 12355;
        location = /status {
            return 502;
        }
    }

    server {
        listen 12356;
        location = /status {
            return 404;
        }
    }

    server {
        listen 12360;
        location = /status {
            return 200;
        }
    }

    server {
        listen 12361;
        location = /status {
            return 200;
        }
    }

    init_by_lua '
        local config = require "config_dyconfig_opts"
        local checkups = require "resty.checkups"
        checkups.prepare_checker({global = config.global})
    ';

    init_worker_by_lua '
        local checkups = require "resty.checkups"
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

=== TEST 1: rr to consistent hash
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            ngx.sleep(1)

            local config = require "config_dyconfig_opts"
            -- update_upstream to rr
            ok, err = checkups.update_upstream("dyconfig", config.dyconfig_rr)
            if err then ngx.say(err) end
            ngx.sleep(2)

            local cb_ok = function(host, port)
                ngx.say(host .. ":" .. port)
                return 1
            end


            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/ab"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/ab"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/abc"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/abc"})


            -- update_upstream to hash
            ok, err = checkups.update_upstream("dyconfig", config.dyconfig_hash)
            if err then ngx.say(err) end
            ngx.sleep(2)

            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/ab"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/ab"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/abc"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/abc"})
        ';
    }
--- request
GET /t
--- response_body
127.0.0.1:12355
127.0.0.1:12356
127.0.0.1:12355
127.0.0.1:12356
127.0.0.1:12354
127.0.0.1:12354
127.0.0.1:12354
127.0.0.1:12354
--- timeout: 10


=== TEST 2: consistent hash continue
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            ngx.sleep(1)

            local config = require "config_dyconfig_opts"

            local cb_ok = function(host, port)
                ngx.say(host .. ":" .. port)
                return 1
            end

            -- update_upstream to hash
            ok, err = checkups.update_upstream("dyconfig", config.dyconfig_hash)
            if err then ngx.say(err) end
            ngx.sleep(2)

            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/ab"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/ab"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/abc"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/abc"})

            -- update_upstream
            ok, err = checkups.update_upstream("dyconfig", config.dyconfig_rr.cluster)
            if err then ngx.say(err) end
            ngx.sleep(2)

            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/ab"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/ab"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/abc"})
            local ok, err = checkups.ready_ok("dyconfig", cb_ok, {hash_key = "/abc"})
        ';
    }
--- request
GET /t
--- response_body
127.0.0.1:12354
127.0.0.1:12354
127.0.0.1:12354
127.0.0.1:12354
127.0.0.1:12355
127.0.0.1:12355
127.0.0.1:12355
127.0.0.1:12355
--- timeout: 10
