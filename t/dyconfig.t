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

    init_worker_by_lua '
        local config = require "config_dyconfig"
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
            checkups.create_checker()
            ngx.sleep(2)

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
            ngx.sleep(1)
            ok, err = checkups.ready_ok("ups1", callback)
            if err then ngx.say(err) end

            -- add server to primary level
            ok, err = checkups.update_upstream("ups1", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12353},
                            {host="127.0.0.1", port=12350},
                        }
                    },
                })
            if err then ngx.say(err) end
            ngx.sleep(1)
            ok, err = checkups.ready_ok("ups1", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups1", callback)
            if err then ngx.say(err) end

            -- add server to primary level, ups2, server exists
            ok, err = checkups.update_upstream("ups2", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12350},
                        }
                    },
                })
            if err then ngx.say(err) end
            ngx.sleep(1)
            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end

            -- add server to primary level, ups2, reset rr state
            ok, err = checkups.update_upstream("ups2", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12350},
                            {host="127.0.0.1", port=12351},
                        }
                    },
                })
            if err then ngx.say(err) end
            ngx.sleep(1)
            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end
        ';
    }
--- request
GET /t
--- response_body
no upstream available
12353
12353
12350
12350
12350
12351

--- timeout: 10


=== TEST 2: Delete server
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
            checkups.create_checker()
            ngx.sleep(2)

            local callback = function(host, port)
                local res = ngx.location.capture("/" .. port)
                ngx.say(res.body)
                return 1
            end

            local ok, err
            -- ups5, delete non-exist level
            ok, err = checkups.delete_upstream("ups5")
            if err then ngx.say(err) end

            ok, err = checkups.delete_upstream("ups2")
            if err then ngx.say(err) end

            ngx.sleep(1)

            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end

            -- add server to primary level, ups2, reset rr state
            ok, err = checkups.update_upstream("ups2", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12350},
                            {host="127.0.0.1", port=12351},
                        }
                    },
                })
            if err then ngx.say(err) end
            ngx.sleep(1)
            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end

            -------------------------------

            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end

            ok, err = checkups.delete_upstream("ups3")
            if err then ngx.say(err) end

            ngx.sleep(1)

            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end

            -- add server to primary level, ups3, reset rr state
            ok, err = checkups.update_upstream("ups3", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12352},
                            {host="127.0.0.1", port=12353},
                        }
                    },
                })
            if err then ngx.say(err) end
            ngx.sleep(1)
            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end
        ';
    }
--- request
GET /t
--- response_body
upstream ups5 not found
unknown skey ups2
12350
12351
12350
12351
12350
12351
unknown skey ups3
12352
12353

--- timeout: 10


=== TEST 3: add, delete servers extracted from nginx upstream
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
            checkups.create_checker()
            ngx.sleep(2)

            local callback = function(host, port)
                local res = ngx.location.capture("/" .. port)
                ngx.say(res.body)
                return 1
            end

            local ok, err
            ok, err = checkups.delete_upstream("ups3")
            if err then ngx.say(err) end

            ngx.sleep(1)

            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end

            -- add server to primary level
            ok, err = checkups.update_upstream("ups3", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12352},
                        }
                    },
                })
            if err then ngx.say(err) end
            ngx.sleep(1)

            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups3", callback)
            if err then ngx.say(err) end
        ';
    }
--- request
GET /t
--- response_body
unknown skey ups3
unknown skey ups3
12352
12352

--- timeout: 10


=== TEST 4: update servers
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
            checkups.create_checker()
            ngx.sleep(2)

            local callback = function(host, port)
                local res = ngx.location.capture("/" .. port)
                ngx.say(res.body)
                return 1
            end

            local ok, err
            ok, err = checkups.update_upstream("ups2", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12350},
                            {host="127.0.0.1", port=12351},
                            {host="127.0.0.1", port=12352},
                            {host="127.0.0.1", port=12353},
                        }
                    },
                })
            if err then ngx.say(err) end

            ngx.sleep(1)

            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("ups2", callback)
            if err then ngx.say(err) end
        ';
    }
--- request
GET /t
--- response_body
12350
12351
12352
12353

--- timeout: 10


=== TEST 5: add new upstream
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
            checkups.create_checker()
            ngx.sleep(2)

            local callback = function(host, port)
                local res = ngx.location.capture("/" .. port)
                ngx.say(res.body)
                return 1
            end

            local ok, err

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end

            ok, err = checkups.update_upstream("new_ups", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12350},
                            {host="127.0.0.1", port=12351},
                            {host="127.0.0.1", port=12352},
                            {host="127.0.0.1", port=12353},
                        }
                    },
                })
            if err then ngx.say(err) end

            ngx.sleep(1)

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
        ';
    }
--- request
GET /t
--- response_body
unknown skey new_ups
12350
12351
12352
12353
12350

--- timeout: 10


=== TEST 6: add new server to new upstream
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
            checkups.create_checker()
            ngx.sleep(2)

            local callback = function(host, port)
                local res = ngx.location.capture("/" .. port)
                ngx.say(res.body)
                return 1
            end

            local ok, err

            ok, err = checkups.delete_upstream("new_ups")
            if err then ngx.say(err) end

            ok, err = checkups.update_upstream("new_ups", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12350},
                            {host="127.0.0.1", port=12351},
                            {host="127.0.0.1", port=12352},
                            {host="127.0.0.1", port=12353},
                        }
                    },
                })
            if err then ngx.say(err) end

            ok, err = checkups.delete_upstream("new_ups")
            if err then ngx.say(err) end

            ok, err = checkups.delete_upstream("new_ups")
            if err then ngx.say(err) end

            ngx.sleep(1)

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end

            ok, err = checkups.update_upstream("new_ups", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12352},
                            {host="127.0.0.1", port=12353},
                            {host="127.0.0.1", port=12350},
                        }
                    },
                })
            if err then ngx.say(err) end
            ngx.sleep(1)

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end

            ok, err = checkups.delete_upstream("new_ups")
            if err then ngx.say(err) end

            ngx.sleep(1)

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
        ';
    }
--- request
GET /t
--- response_body
upstream new_ups not found
upstream new_ups not found
unknown skey new_ups
unknown skey new_ups
12352
12353
12350
unknown skey new_ups

--- timeout: 10


=== TEST 7: add new level to new upstream
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
            checkups.create_checker()
            ngx.sleep(2)

            local callback = function(host, port)
                local res = ngx.location.capture("/" .. port)
                ngx.say(res.body)
                return 1
            end

            local ok, err

            ok, err = checkups.update_upstream("new_ups", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12350},
                            {host="127.0.0.1", port=12351},
                        }
                    },
                })
            if err then ngx.say(err) end

            ngx.sleep(1)

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end

            ok, err = checkups.update_upstream("new_ups", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12350},
                            {host="127.0.0.1", port=12351},
                            {host="127.0.0.1", port=12352},
                            {host="127.0.0.1", port=12353},
                        }
                    },
                })

            ngx.sleep(1)

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end

            ok, err = checkups.delete_upstream("new_ups")
            if err then ngx.say(err) end
            ngx.sleep(1)

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end

            ok, err = checkups.update_upstream("new_ups", {
                    {
                        servers = {
                            {host="127.0.0.1", port=12352},
                            {host="127.0.0.1", port=12353},
                        }
                    },
                })

            ngx.sleep(1)

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end

            ok, err = checkups.ready_ok("new_ups", callback)
            if err then ngx.say(err) end
        ';
    }
--- request
GET /t
--- response_body
12350
12351
12350
12351
12352
12353
12350
12351
unknown skey new_ups
12352
12353

--- timeout: 10
