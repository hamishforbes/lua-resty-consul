lua-resty-consul
================

Library to interface with the consul HTTP API from ngx_lua

# Table of Contents

* [Overview](#overview)
* [Dependencies](#dependencies)
* [Basic Methods](#basic_methods)
    * [new](#new)
    * [get](#get)
    * [put](#put)
    * [delete](#delete)
    * [get_client_body_reader](#get_client_body_reader)
* [Key Value helpers](#key_value_helpers)
    * [get_key](#get_key)
    * [put_key](#put_key)
    * [delete_key](#delete_key)
    * [list_keys](#list_keys)
* [Transaction helpter](#transaction_helper)

# Overview

Methods all return a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
The response body has been read and set to `res.body`, JSON decoded if the response has a `Content-Type` header of `Application/JSON`.

All response headers are available at `res.headers`.

The ACL Token parameter is always sent as the `X-Consul-Token` header rather than being included in the query string.

If `wait` or `index` arguments are provided the request read timeout is extended appropriately.  
`wait` must be passed as a number of seconds, do not include `s` or any other unit string.

```lua

local resty_consul = require('resty.consul')
local consul = resty_consul:new({
        host            = "127.0.0.1",
        port            = 8500,
        connect_timeout = (60*1000), -- 60s
        read_timeout    = (60*1000), -- 60s
        default_args    = {
            token = "my-default-token"
        },
        ssl             = false,
        ssl_verify      = true,
        sni_host        = nil,
    })

local res, err = consul:get('/agent/services')
if not res then
    ngx.log(ngx.ERR, err)
    return
end

ngx.print(res.status) -- 200
local services = res.body -- JSON decoded response


local res, err = consul:put('/agent/service/register', my_service_definition, { token = "override-token" })
if not res then
    ngx.log(ngx.ERR, err)
    return
end

ngx.print(res.status) -- 200
ngx.print(res.headers["X-Consul-Knownleader"]) -- "true"
local service_register_response = res.body -- JSON decoded response


local res, err = consul:list_keys() -- Get all keys
if not res then
    ngx.log(ngx.ERR, err)
    return
end

local keys = {}
if res.status == 200 then
    keys = res.body
end

for _, key in ipairs(keys) do
    local res, err = consul:get_key(key)
    if not res then
        ngx.log(ngx.ERR, err)
        return
    end

    ngx.print(res.body[1].Value) -- Key value after base64 decoding
end
```

# Dependencies

 * [lua-resty-http](https://github.com/pintsized/lua-resty-http)

# Basic Methods

### new

`syntax: client = consul:new(opts?)`

Create a new consul client. `opts` is a table setting the following options:

 * `host` Defaults to 127.0.0.1
 * `port` Defaults to 8500. Set to `0` if using a unix socket as `host`.
 * `connect_timeout` Connection timeout in ms. Defaults to 60s
 * `read_timeout` Read timeout in ms. Defaults to 60s
 * `default_args` Table of query string arguments to send with all requests (e.g. `token`) Defaults to empty
 * `ssl` Boolean, enable HTTPS requests. Default to `false`.
 * `ssl_verify` Boolean, verify SSL certificates. Defaults to `true`      = true,
 * `sni_host` Hostname to use when verifying SSL certs.

### get

`syntax: res, err = consul:get(path, args?)`

Performs a GET request to the provided path. API Version is automatically prepended.

`args` is a table of query string parameters to add to the URI.

Returns a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
On error returns `nil` and an error message.


### put

`syntax: res, err = consul:put(path, body, args?)`

Performs a PUT request to the provided path. API Version is automatically prepended.

`args` is table of query string parameters to add to the URI.

If `body` is a table or boolean value it is automatically json encoded before being sent.   
Otherwise anything that [lua-resty-http](https://github.com/pintsized/lua-resty-http) accepts as a body input is valid.

Returns a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
On error returns `nil` and an error message.

### delete

`syntax: res, err = consul:delete(path, args?)`

Performs a GET request to the provided path. API Version is automatically prepended.

`args` is a table of query string parameters to add to the URI.

Returns a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
On error returns `nil` and an error message.

### get_client_body_reader

Proxy method to [lua-resty-http](https://github.com/pintsized/lua-resty-http#get_client_body_reader)

# Key Value Helpers

These methods automatically prepend `/v1/kv`, only the actual key should be passed.  
Base64 encoded values are automatically decoded.

### get_key

`syntax: res, err = consul:get_key(key, args?)`

Retrieve a Consul KV key. Values are Base64 decoded.

`args` is a table of query string parameters to add to the URI.

Returns a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
On error returns `nil` and an error message.

### put_key

`syntax: res, err = consul:put_key(key, value, args?)`

Create or update a KV key.

`args` is table of query string parameters to add to the URI.

If `value` is a table or boolean value it is automatically json encoded before being sent.   
Otherwise anything that [lua-resty-http](https://github.com/pintsized/lua-resty-http) accepts as a body input is valid.

Returns a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
On error returns `nil` and an error message.

### delete

`syntax: res, err = consul:delete_key(key, args?)`

Delete a KV entry.

`args` is a table of query string parameters to add to the URI.

Returns a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
On error returns `nil` and an error message.


### list_keys

`syntax: res, err = consul:list_keys(prefix?, args?)`

Retrieve all the keys in the KV strore. Optionally within a `prefix`.

`args` is a table of query string parameters to add to the URI.   
`keys` is always set as a query string parameter with this method

Returns a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
On error returns `nil` and an error message.


# Transaction helper

### txn

`syntax: res, err = consul:txn(payload, args?)`

Performs a `PUT` request  to the `/v1/txn` API endpoint with the provided payload.

`payload` can be provided as a Lua table, in which case `Value` keys will be automatically base64 encoded.  
Otherwise anything that [lua-resty-http](https://github.com/pintsized/lua-resty-http) accepts as a body input is valid.

Returns a [lua-resty-http](https://github.com/pintsized/lua-resty-http) response object.  
On error returns `nil` and an error message.

KV values in the response body are automatically base64 decoded.

```lua
local txn_payload = {
    {
        KV = {
            Verb   = "set",
            Key    = "foo",
            Value  = "bar",
        }
    },
    {
        KV = {
            Verb   = "get",
            Key    = "foobar",
        }
    }
}

local consul = resty_consul:new()

local res, err = consul:txn(txn_payload)
if not res then
    ngx.say(err)
    return
end

ngx.say(res.body.Results[2].KV.Value) -- "bar"
```

