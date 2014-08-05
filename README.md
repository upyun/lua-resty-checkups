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
    checkup_timer_interval = 2,
    checkup_timer_overtime = 10,
}

_M.api = {
    timeout = 2,
    typ = "general",

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
    http_opts = {
        query = "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n",
        statuses = {
            [502] = false,
        },
    },

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
                { host = "127.0.0.1", port = 12350 },
                { host = "127.0.0.1", port = 12351 },
            }
        },
    },
}


return _M

```


#### 集群配置

> 以 Newworld 为例

```
_M.newworld = {
    timeout = 5,
    read_timeout = 30,
    send_timeout = 60,

    cluster = {
        {   -- level 1
            try = 2,
            servers = {
                { host = "127.0.0.1", port = 8080 },
            }
        },
        {   -- level 2
            servers = {
                { host = "192.168.0.71", port = 8080 },
                { host = "192.168.0.72", port = 8080 },
                { host = "192.168.0.73", port = 8080 },
            }
        },
    },
}
```

> timeout, read_timeout, send_timeout

分别表示连接超时，读超时和写超时，特别地，当没有明确设置 read_timeout 或 send_timeout 的情况下， 其值都以 timeout 为准.

> cluster = { { -- level 1 }, { -- level 2 } }

这是 Kuzan 特有的一个集群配置结构，目前支持一些简单的容灾（主备及重试机制）和负载均衡（Round Robin）处理，如上所示，可以按优先级配置多个 level，每个 level 下可以配置一个 server 集群，Kuzan 会根据 level 优先级默认总是使用 level 1 的集群，只有当 level 1 的集群全部可不用的时候，自动切换到 level 2，以此类推; 因此，此时要配置简单的主备模式就很方便了，配置两个 level，每个  level 一台 server 即可.

> { try = 2, servers = { { host = "127.0.0.1", port = 8080 } } }

这是 cluster 每层 level 的配置结构，其中 servers 中可配置多个后端，目前后端配置只支持 host/port 形式，接下来会考虑对  unixsock 形式的支持，另外多台 server 默认会进行简单地 Round Robin 轮询，实现一定地负载均衡效果；try 表示失败重试几次，默认是 servers 的数量（跟 Nginx 的 upstream 非常类似），当某次请求检测到该层 level 的某台 server 不可用的时候，会切换到下一台进行重试，若一直失败，则重复这个过程，但最多只会重试 try 次，特别地，若某一层的 try 设置的值大于其 servers 的数量，那么，当该层的 servers 均不可用的情况下，level 会自动切换到下一层（如有有的话），如上配置所示，level 1 只配置了 1 台 server，但 try 设置的是 2，那么当这台唯一的 server 不可用的时候，当前请求的重试机制会切换到下一层的 level，即 level 2，此处配置了 3 个 server， try 默认是 server 个数 3，那么此时就完全按照 level 2 的规则来进行重试和负载均衡了.

另外，这个集群配置结构在结合主动健康检查的情况下，会动态调整，例如若 level 1 中某台 server 或者整个 level 1 不可用的时候，会自动临时剔除这些不可用的配置，重新排列配置结构，并且仍然会按照以上规则进行处理.


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
                    return 1
            	end

            	local res = checkups.ready_ok("status", cb_ok)
            	local res = checkups.ready_ok("status", cb_ok)
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

`syntax: res = checkups.ready_ok(callback)`


## get_status

`syntax: status = checkups.get_status()`
