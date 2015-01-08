lua-resty-consul
================

Library to interface with the consul HTTP API from ngx_lua

#Table of Contents

* [Overview](#overview)
* [Dependencies](#dependencies)
* [Methods](#methods)
    * [new](#new)
    * [get](#get)
    * [get_decoded](#get_decoded)
    * [get_json_decoded](#get_json_decoded)
    * [get_decoded](#get_decoded)
    * [put](#put)
    * [delete](#delete)
    * [get_client_body_reader](#get_client_body_reader)

# Overview

```lua

local resty_consul = require('resty.consul')
local consul = resty_consul:new({
        host = 10.10.10.10,
        port = 8500
    })

local ok, err = consul:put('/kv/foobar', 'My key value!')
if not ok then
    ngx.log(ngx.ERR, err)
end

local ok, err = consul:put('/kv/some_json', { msg = 'This will be json encoded'})
if not ok then
    ngx.log(ngx.ERR, err)
end

local res,err = consul:get('/kv/foobar')
if not res then
    ngx.log(ngx.ERR, err)
end
ngx.say(res.Value) -- Prints "TXkga2V5IHZhbHVlIQo="

local res,err = consul:get_decoded('/kv/foobar')
if not res then
    ngx.log(ngx.ERR, err)
end
ngx.say(res.Value) -- Prints "My key value!"

local res, err = consul:get_json_decoded('/kv/some_json')
if not res then
    ngx.log(ngx.ERR, err)
end
if type(res.Value) == 'table' then
    ngx.say(res.Value.msg) -- Prints "This will be json encoded"
else
    ngx.log(ngx.ERR, "Failed to decode value :(")
end

```


# Dependencies

 * [lua-resty-http](https://github.com/pintsized/lua-resty-http)

# Methods

### new

`syntax: client = consul:new(opts?)`

Create a new consul client. `opts` is a table setting the following options:

 * `host` Defaults to 127.0.0.1
 * `port` Defaults to 8500
 * `connect_timeout` Connection timeout in ms. Defaults to 60s
 * `read_timeout` Read timeout in ms. Defaults to 60s

### get

`syntax: res, headers = consul:get(key, opts?)`

Performs a GET request against the provided key. API Version is automatically prepended.

e.g. to get the value of a key at http://my.consul.server/v1/kv/foobar you would call `consul:get('/kv/foobar')`

`opts` is hash of query string parameters to add to the URI.

The `wait` query string param is a special case, it must be passed in as an number not as a string with 's' appended.

Returns a table representing the response from Consul and a second table of the Consul specific headers `X-Consul-Lastcontact`, `X-Consul-KnownLeader` and `X-Consul-Index`.

On error returns `nil` and an error message.

### get_decoded

`syntax: res, headers = consul:get_decoded(key, opts?)`

Wrapper on the `get` method, but performs base64 decode on the `value` field in the Consul response

### get_json_decoded

`syntax: res, headers = consul:get_json_decoded(key, opts?)`

Wrapper on the `get` method, but performs base64 decode on the `value` field in the Consul response and then attempts to parse the value as json.

### put

`syntax: res, err = consul:put(key, value, opts?)`

Performs a PUT request against the provided key with provided value. API Version is automatically prepended.

`opts` is hash of query string parameters to add to the URI.

If `value` is a table or boolean value it is automatically json encoded before being sent.

Otherwise anything that [lua-resty-http](https://github.com/pintsized/lua-resty-http) accepts as a body input is valid.

On a 200 response returns the response body if there is one or a boolean true.

On a non-200 response returns nil and the response body.

### delete

`syntax: ok, err = consul:delete(key, value, recurse?)`

Performs a DELETE request against the provided key. 

`recurse` defaults to false.

Returns a boolean true if the response is 200.

Otherwise a table containing `status`, `body` and `headers` as well as the error from [lua-resty-http](https://github.com/pintsized/lua-resty-http)

### get_client_body_reader

Proxy method to [lua-resty-http](https://github.com/pintsized/lua-resty-http#get_client_body_reader)
