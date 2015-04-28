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
$ENV{TEST_NGINX_PWD} = $pwd;

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

            for i = 1, 5, 1 do
                local ok, err = checkups.ready_ok("multi_level", cb_ok)
                if i ~= 5 then
                    ngx.print(" ")
                end
            end
        ';
    }
--- request
GET /t
--- response_body: EFH EFH EFH EFH EFH

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

            for i = 1, 5, 1 do
                local ok, err = checkups.ready_ok("multi_key", cb_ok, {cluster_key = {default = "c1", backup = "c2"}})
                if i ~= 5 then
                    ngx.print(" ")
                end
            end
        ';
    }
--- request
GET /t
--- response_body: EFH EFH EFH EFH EFH

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
                ngx.print(" ")
                ngx.say(err)
            end
        ';
    }
--- request
GET /t
--- response_body
FH round robin: no servers available
--- timeout: 10

=== TEST 7: Round robin interface
--- http_config eval
"$::HttpConfig" . "$::InitConfig"
--- config
    location = /t {
        content_by_lua_file $TEST_NGINX_PWD/t/lib/round_robin_interface.lua;
    }
--- request
GET /t
--- response_body
G0ADE 3 FA round robin: no servers available
0AEA 1 F round robin: no servers available
0AEA 1 F round robin: no servers available
0AEA 1 F round robin: no servers available
0AEA 1 F round robin: no servers available

G0ADE 3 FA round robin: no servers available
0AEA 1 F round robin: no servers available
0AEA 1 F round robin: no servers available
0AEA 1 F round robin: no servers available
0AEA 1 F round robin: no servers available

 0AE 3 FA round robin: no servers available
 0AEA 1 F round robin: no servers available
 0AEA 1 F 0AE 3 F 0AE 3 F

0A port: 12351
0A port: 12351
0A port: 12351
0A port: 12351
0A port: 12351

0000A0A000A0A000A0A0|
--- timeout: 30
