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
=== TEST 1: KV Get Request - decoded
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local res, err = c:get_kv('foobar')
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.body[1].Value)
            ngx.say(res.status)
            ngx.say(res.headers["X-Consul-Index"])
            ngx.say(res.headers["X-URI"])
        }
    }
    location / {
        content_by_lua_block {
            opts.body = {
                {
                    ModifyIndex = 2,
                    CreateIndex = 1,
                    Value = "dGVzdCB2YWw=",
                    Flags = 0,
                    Key = "foobar",
                    LockIndex = 0
                }
            }
            opts.headers["X-Consul-Index"] = 2
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
test val
200
2
/v1/kv/foobar

=== TEST 2: KV PUT Request
--- http_config eval
"$::HttpConfig"
--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local res, err = c:put_kv('foobar', { newval = baz })
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
/v1/kv/foobar

=== TEST 3: KV DELETE Request
--- http_config eval
"$::HttpConfig"
--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local res, err = c:delete_kv('foobar', { recurse = true })
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
/v1/kv/foobar
recurse
