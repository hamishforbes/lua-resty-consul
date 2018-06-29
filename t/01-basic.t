use Test::Nginx::Socket 'no_plan';
use Cwd qw(cwd);

my $pwd = cwd();

$ENV{TEST_LEDGE_REDIS_DATABASE} ||= 1;
$ENV{TEST_NGINX_PORT} |= 1984;


our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    init_by_lua_block {
        require("resty.consul")._debug(true)

        TEST_NGINX_PORT = $ENV{TEST_NGINX_PORT}

        opts = {
            body = "CONSUL OK",
            headers = {
                ["Content-Type"] = "application/json",
                ["Vary"] = "Accept-Encoding",
                --["X-Consul-Effective-Consistency"] = "leader",
                ["X-Consul-Index"] = 0,
                ["X-Consul-Knownleader"] = "true",
                ["X-Consul-Lastcontact"] = 0,
            },
            status = 200
        }

        function mockConsul(opts)
            ngx.status = opts.status

            for k, v in pairs(opts.headers) do
                ngx.header[k] = tostring(v)
            end
            ngx.header["X-Method"] = ngx.req.get_method()
            ngx.header["X-URI"]    = ngx.var.uri
            ngx.header["X-Args"]   = ngx.var.args
            ngx.header["X-Token"]  = ngx.req.get_headers()["X-Consul-Token"]

            if opts.no_encode then
                ngx.print(opts.body)
            else
                ngx.print(require("cjson").encode(opts.body))
            end

            return ngx.exit(ngx.status)
        end
    }
};


no_long_string();
no_root_location();
run_tests();

__DATA__
=== TEST 1: Module loads
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            ngx.say("OK")
            local c = consul:new()
            ngx.say("OK2")
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
OK
OK2

=== TEST 2: Get Request
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local res, err = c:get('/dummy/foobar')
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.body)
            ngx.say(res.status)
            ngx.say(res.headers["X-URI"])

            local res, err = c:get('/dummy/foobar2', {keys = true, test = 123})
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.headers["X-URI"])
            ngx.say(res.headers["X-Args"]:find("keys", 1, true) ~= nil)
            ngx.say(res.headers["X-Args"]:find("test=123", 1, true) ~= nil)
        }
    }
    location / {
        content_by_lua_block {
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
CONSUL OK
200
/v1/dummy/foobar
/v1/dummy/foobar2
true
true

=== TEST 3: PUT Request
--- http_config eval
"$::HttpConfig"
--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local res, err = c:put('/dummy/foobar', { newval = baz })
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
            ngx.say(type(res.body))
            ngx.say(res.body)
            ngx.say(res.headers["X-Method"])
            ngx.say(res.headers["X-URI"])
        }
    }
    location / {
        content_by_lua_block {
            opts.body = "true"
            opts.no_encode = true
            opts.headers["X-Consul-Index"] = nil
            opts.headers["X-Consul-Knownleader"] = nil
            opts.headers["X-Consul-Lastcontact"] = nil
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
200
boolean
true
PUT
/v1/dummy/foobar

=== TEST 4: DELETE Request
--- http_config eval
"$::HttpConfig"
--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local res, err = c:delete('/dummy/foobar', { recurse = true })
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
            ngx.say(type(res.body))
            ngx.say(res.body)
            ngx.say(res.headers["X-Method"])
            ngx.say(res.headers["X-URI"])
            ngx.say(res.headers["X-Args"])
        }
    }
    location / {
        content_by_lua_block {
            opts.body = "true"
            opts.no_encode = true
            opts.headers["X-Consul-Index"] = nil
            opts.headers["X-Consul-Knownleader"] = nil
            opts.headers["X-Consul-Lastcontact"] = nil
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
200
boolean
true
DELETE
/v1/dummy/foobar
recurse

=== TEST 5: Default args come through
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({
                port = TEST_NGINX_PORT,
                default_args = {
                    default = "123"
                }
            })

            local res, err = c:get('/dummy/foobar')
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.headers["X-Args"]:find("default=123", 1, true) ~= nil)
        }
    }
    location / {
        content_by_lua_block {
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
true

=== TEST 6: Default args are merged
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({
                port = TEST_NGINX_PORT,
                default_args = {
                    default = "123",
                    override_me = "bad",
                }
            })

            local res, err = c:get('/dummy/foobar2', {test = 123, override_me = "good"})
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.headers["X-Args"]:find("test=123", 1, true) ~= nil)
            ngx.say(res.headers["X-Args"]:find("default=123", 1, true) ~= nil)
            ngx.say(res.headers["X-Args"]:find("override_me=bad", 1, true) ~= nil)
            ngx.say(res.headers["X-Args"]:find("override_me=good", 1, true) ~= nil)
        }
    }
    location / {
        content_by_lua_block {
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
true
true
false
true

=== TEST 6: Token is only sent by header
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({
                port = TEST_NGINX_PORT,
                default_args = {
                    token = "123"
                }
            })

            local res, err = c:get('/dummy/foobar')
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(type(res.headers["X-Args"]))
            ngx.say(res.headers["X-Token"])
        }
    }
    location / {
        content_by_lua_block {
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
nil
123

=== TEST 7: Get Request with wait
--- http_config eval
"$::HttpConfig"
--- config
    lua_socket_log_errors off;
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT, read_timeout = 100 })

            local res, err = c:get('/dummy/foobar', { wait = 0.1 })
            if not res then
                ngx.say(err)
                ngx.log(ngx.DEBUG, err)
                return
            else
                ngx.say("OK")
            end
        }
    }
    location / {
        content_by_lua_block {
            ngx.sleep(0.5)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- error_log
Blocking query timeout: 206.25
--- response_body
timeout

=== TEST 7: Missing params
--- http_config eval
"$::HttpConfig"
--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local res, err = c:get()
            assert(res == nil, "get with no path")
            local res, err = c:get({})
            assert(res == nil, "get with non-string path")

            local res, err = c:put()
            assert(res == nil, "put with no path")
            local res, err = c:put('foo')
            assert(res == nil, "put with only path, no body")
            local res, err = c:put({})
            assert(res == nil, "put with non-string path")

            local res, err = c:delete()
            assert(res == nil, "delete with no path")
            local res, err = c:delete({})
            assert(res == nil, "delete with non-string path")

            ngx.say("OK")

        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
OK
