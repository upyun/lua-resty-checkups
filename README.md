lua-resty-checkups
====

Health-checker for [ngx-lua](https://github.com/chaoslawful/lua-nginx-module) upstream servers


Status
======

This library is still under early development.

Configure
======

```

--config.lua
	
_M = {}

_M.global = {
    positive_check = true,
    passive_check = true,
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.api = {
    timeout = 2,
    typ = "general",
    max_fails = 1,

    cluster = {
        {   -- level 1
            try = 2,
            servers = {
                { host = "127.0.0.1", port = 12354 },
                { host = "127.0.0.1", port = 12355 },
                { host = "127.0.0.1", port = 12356 },
            }
        },
        {   -- level 2
            servers = {
                { host = "127.0.0.1", port = 12360 },
                { host = "127.0.0.1", port = 12361 },
            }
        },
    },
}
	
_M.status = {
    timeout = 2,
    typ = "http",
    heartbeat_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
        statuses = {
            [200] = true,
            [404] = true,
            [502] = false,
        },
    },
    max_fails = 1,

    cluster = {
        {   -- level 1
            try = 2,
            servers = {
                { host = "127.0.0.1", port = 12354 },
                { host = "127.0.0.1", port = 12355 },
                { host = "127.0.0.1", port = 12356 },
                { host = "127.0.0.1", port = 12357 },
            }
        },
        {   -- level 2
            servers = {
                { host = "127.0.0.1", port = 12360 },
                { host = "127.0.0.1", port = 12361 },
            }
        },
    },
}


return _M

```

Synopsis
========


```
nginx.conf

http {
	lua_package_path "$pwd/../lua-resty-lock/?.lua;$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    
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
        listen 12357;
        location = /status {
            content_by_lua '
                ngx.sleep(3)
                ngx.status = 200
            ';
        }
    }

	server {
		listen 9090;

		location = /t {
    		init_by_lua '
        		local config = require "config"
        		local checkups = require "resty.checkups"
        		checkups.prepare_checker(config)
    		';

     		content_by_lua '
            	local checkups = require "resty.checkups"
            	checkups.create_checker()
            	ngx.sleep(5)
            	local cb_ok = function(host, port)
                	ngx.say(host .. ":" .. port)
            	end

            	local ok, err = checkups.ready_ok("status", cb_ok)
            	if err then
                	ngx.say(err)
            	end
            	local ok, err = checkups.ready_ok("status", cb_ok)
            	if err then
                	ngx.say(err)
            	end
        	';
		}
	}
}
```

A typical output of the `\t` location is

```
127.0.0.1:12354
127.0.0.1:12356
```


Methods
=======

## prepare_checker


`syntax: checkups.prepare_checker(config)`


## create_checker

`syntax: checkups.create_checker()`


## ready_ok

`syntax: res, err = checkups.ready_ok(callback)`


## get_status

`syntax: status = checkups.get_status()`




