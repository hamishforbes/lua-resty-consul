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
=== TEST 1: TXN Request, table input
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local txn_payload = {
                {
                    KV = {
                        Verb   = "set",
                        Key    = "foobar",
                        Value  = "testval",
                        Flags  = nil,
                        Index  = nil,
                        Session = nil
                    }
                },
                {
                    KV = {
                        Verb   = "get",
                        Key    = "foobar",
                    }
                }
            }

            local res, err = c:txn(txn_payload)
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.body.Results[2].KV.Value)
            ngx.say(res.status)
            ngx.say(res.headers["X-Consul-Index"])
            ngx.say(res.headers["X-URI"])
        }
    }
    location / {
        content_by_lua_block {
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            body = require("cjson").decode(body)


            opts.body = {
                Results = {
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags =  0,
                            Value = ngx.null,
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    },
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags = 0,
                            Value = body[1].KV.Value,
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    }
                },
                Errors = ngx.null
            }
            opts.headers["X-Consul-Index"] = 283839
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
testval
200
283839
/v1/txn

=== TEST 2: TXN Request, json input does not encode
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local txn_payload = {
                {
                    KV = {
                        Verb   = "set",
                        Key    = "foobar",
                        Value  = "test val",
                        Flags  = nil,
                        Index  = nil,
                        Session = nil
                    }
                },
                {
                    KV = {
                        Verb   = "get",
                        Key    = "foobar",
                    }
                }
            }

            local res, err = c:txn(require("cjson").encode(txn_payload))
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.body.Results[2].KV.Value)
            ngx.say(res.status)
            ngx.say(res.headers["X-Consul-Value"])
            ngx.say(res.headers["X-URI"])
        }
    }
    location / {
        content_by_lua_block {
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            body = require("cjson").decode(body)
            opts.headers["X-Consul-Value"] = body[1].KV.Value
            opts.body = {
                Results = {
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags =  0,
                            Value = ngx.null,
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    },
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags = 0,
                            Value = "dGVzdCB2YWw=",
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    }
                },
                Errors = ngx.null
            }
            opts.headers["X-Consul-Index"] = 283839
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
test val
/v1/txn

=== TEST 3: TXN Request args pass through
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local txn_payload = {
                {
                    KV = {
                        Verb   = "set",
                        Key    = "foobar",
                        Value  = "testval",
                        Flags  = nil,
                        Index  = nil,
                        Session = nil
                    }
                },
                {
                    KV = {
                        Verb   = "get",
                        Key    = "foobar",
                    }
                }
            }

            local res, err = c:txn(txn_payload, { test = "123"})
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.body.Results[2].KV.Value)
            ngx.say(res.status)
            ngx.say(res.headers["X-Consul-Index"])
            ngx.say(res.headers["X-Args"]:find("test=123", 1, true) ~= nil)
        }
    }
    location / {
        content_by_lua_block {
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            body = require("cjson").decode(body)


            opts.body = {
                Results = {
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags =  0,
                            Value = ngx.null,
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    },
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags = 0,
                            Value = body[1].KV.Value,
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    }
                },
                Errors = ngx.null
            }
            opts.headers["X-Consul-Index"] = 283839
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
testval
200
283839
true

=== TEST 4: TXN Request, error response
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})

            local txn_payload = {
                {
                    KV = {
                        Verb   = "set",
                        Key    = "foobar",
                        Value  = "testval",
                        Flags  = nil,
                        Index  = nil,
                        Session = nil
                    }
                },
                {
                    KV = {
                        Verb   = "get",
                        Key    = "foobar",
                    }
                }
            }

            local res, err = c:txn(txn_payload)
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.body.Errors.Foo)
            ngx.say(res.status)

        }
    }
    location / {
        content_by_lua_block {
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            body = require("cjson").decode(body)


            opts.body = {
                Results = ngx.null,
                Errors = {Foo = "Bar" }
            }
            opts.headers["X-Consul-Index"] = 283839
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
Bar
200

=== TEST 5: TXN Request, table input, types
--- http_config eval
"$::HttpConfig"

--- config
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({port = TEST_NGINX_PORT})


            local txn_payload = {
                {
                    KV = {
                        Verb   = "set",
                        Key    = "foobar",
                        Value  = 1234,
                        Flags  = nil,
                        Index  = nil,
                        Session = nil
                    }
                },
                {
                    KV = {
                        Verb   = "set",
                        Key    = "foobar2",
                        Value  = true,
                        Flags  = nil,
                        Index  = nil,
                        Session = nil
                    }
                },
                {
                    KV = {
                        Verb   = "get",
                        Key    = "foobar",
                    }
                },
                {
                    KV = {
                        Verb   = "get",
                        Key    = "foobar2",
                    }
                }
            }

            local res, err = c:txn(txn_payload)
            if not res then
                ngx.say(err)
                return
            end

            if res.status ~= 200 then
                ngx.say(ngx.DEBUG, require("cjson").encode(res.body) )
                return
            end

            ngx.say(res.status)
            ngx.say(type(res.body.Results[3].KV.Value))
            ngx.say(res.body.Results[3].KV.Value)
            ngx.say(type(res.body.Results[4].KV.Value))
            ngx.say(res.body.Results[4].KV.Value)
        }
    }
    location / {
        content_by_lua_block {
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            body = require("cjson").decode(body)


            opts.body = {
                Results = {
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags =  0,
                            Value = ngx.null,
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    },
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar2",
                            Flags =  0,
                            Value = ngx.null,
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    },
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags = 0,
                            Value = "MTIzNA==",
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    },
                    {
                        KV = {
                            LockIndex = 0,
                            Key = "foobar",
                            Flags = 0,
                            Value = "dHJ1ZQ==",
                            CreateIndex = 283839,
                            ModifyIndex = 283839
                        }
                    }
                },
                Errors = ngx.null
            }
            opts.headers["X-Consul-Index"] = 283839
            mockConsul(opts)
        }
    }
--- request
GET /a
--- no_error_log
[error]
--- response_body
200
string
1234
string
true
