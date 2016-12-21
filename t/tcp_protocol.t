# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each( 2 );

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_socket_log_errors off;
    lua_package_path "$pwd/../lua-resty-lock/?.lua;$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    error_log logs/error.log debug;

    lua_shared_dict state 10m;
    lua_shared_dict mutex 1m;
    lua_shared_dict locks 1m;

    init_by_lua '
        local config = require "config_protocol"
        local checkups = require "resty.checkups"
        checkups.prepare_checker(config)
    ';

};

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: connect and send hello to redis
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            ngx.sleep(5)
            local config = require "config_protocol"
            local tcp_config = config.tcp_protocol or {}
            local protocol = tcp_config.protocol or {}
            local mod_name = protocol.module
            local mod_config = protocol.config or {}
            local hello = require(mod_name)
            local timeout = (tcp_config.timeout or 2) * 1000
            local _connect = function(host, port)
                local sock, err = hello:new(mod_config)
                if not sock then
                    return nil, err
                end
                sock:settimeout(timeout * 1000)
                local reused, err =  sock:connect(host, port)
                if not reused then
                    return nil, err
                end
                ngx.say(host .. ":" .. port .. " reused: " .. reused)
                return sock
            end
            local sock = checkups.ready_ok("tcp_protocol", _connect)
            sock:setkeepalive(tcp_config.keepalive_timeout, tcp_config.keepalive_size)
            ngx.sleep(1)
            local sock = checkups.ready_ok("tcp_protocol", _connect)
            sock:setkeepalive(tcp_config.keepalive_timeout, tcp_config.keepalive_size)
            ngx.sleep(1)
            local sock = checkups.ready_ok("tcp_protocol", _connect)
            ngx.say(sock:hello())
            sock:close()
        ';
    }

--- request
GET /t
--- response_body
127.0.0.1:6379 reused: 1
127.0.0.1:6379 reused: 2
127.0.0.1:6379 reused: 3
magic identifier
--- no_error_log
[error]
--- timeout: 10
