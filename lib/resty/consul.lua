local pcall = pcall
local cjson = require('cjson')
local json_decode = cjson.decode
local json_encode = cjson.encode
local ngx = ngx
local ngx_null = ngx.null
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG
local ngx_decode_base64 = ngx.decode_base64
local ngx_encode_base64 = ngx.encode_base64
local http = require('resty.http')

local DEBUG = false

local _M = {
    _VERSION = '0.3.2',
}

local API_VERSION     = "v1"
local DEFAULT_HOST    = "127.0.0.1"
local DEFAULT_PORT    = 8500
local DEFAULT_TIMEOUT = 60*1000 -- 60s default timeout

local mt = { __index = _M }


function _M.new(_, args)
    args = args or {}
    local self = {
        host            = args.host            or DEFAULT_HOST,
        port            = args.port            or DEFAULT_PORT,
        connect_timeout = args.connect_timeout or DEFAULT_TIMEOUT,
        read_timeout    = args.read_timeout    or DEFAULT_TIMEOUT,
        default_args    = args.default_args    or {},
        ssl             = args.ssl             or false,
        ssl_verify      = true,
        sni_host        = args.sni_host,
    }

    if args.ssl_verify ~= nil then
        self.ssl_verify = args.ssl_verify
    end

    if self.port == 0 then self.port = nil end

    return setmetatable(self, mt)
end

function _M._debug(debug)
    DEBUG = debug
end


function _M.get_client_body_reader(self, ...)
    return http:get_client_body_reader(...)
end


local function safe_json_decode(json_str)
    local ok, json = pcall(json_decode, json_str)
    if ok then
        return json
    else
        ngx_log(ngx_ERR, json)
    end
end


local function connect(self)
    local httpc = http.new()

    local connect_timeout = self.connect_timeout
    if connect_timeout then
        httpc:set_timeout(connect_timeout)
    end

    local ok, err
    if self.port then
        ok, err = httpc:connect(self.host, self.port)
    else
        ok, err = httpc:connect(self.host)
    end

    if not ok then
        return nil, err
    end

    if self.ssl then
        if DEBUG then ngx_log(ngx_DEBUG, "[Consul ssl] Handshaking, host: ", self.sni_host, " verify: ", self.ssl_verify) end
        local ok, err = httpc:ssl_handshake(nil, self.sni_host, self.ssl_verify)
        if not ok then
            return nil, err
        end
    end

    return httpc
end


-- Generic request function
local function _request(self, method, path, args, body)
    local httpc, err = connect(self)
    if not httpc then
        return nil, err
    end

    args = args or {}

    local uri = "/"..API_VERSION..path

    for k, v in pairs(self.default_args) do
        args[k] = args[k] or v
    end

    local headers = {
        ["X-Consul-Token"] = args.token
    }
    args.token = nil -- remove token from query string

    if not self.port then -- Connecting on unix socket, fake a Host header
        headers["Host"] = "consul.rocks"
    end

    if args.wait or args.index then
        -- Blocking request, increase timeout
        -- https://www.consul.io/api/index.html#blocking-queries
        local timeout = (5 * 60 * 1000) -- Default timeout is 5m
        if args.wait then
            timeout = (args.wait * 1000)
            args.wait = args.wait.."s" -- Append 's' in query string
        end
        if DEBUG then ngx_log(ngx_DEBUG, "[Consul] Blocking query timeout: ", timeout + (timeout / 16) + self.read_timeout) end
        httpc:set_timeout(timeout + (timeout / 16) + self.read_timeout)
    else
        httpc:set_timeout(self.read_timeout)
    end

    local body_type = type(body)

    if body_type == "table" then
        body = json_encode(body)
    elseif body_type == "number" or body_type == "boolean" then
        body = tostring(body)
    end

    local params = {
        path    = uri,
        headers = headers,
        method  = method,
        query   = args,
        body    = body,
    }

    local res, err = httpc:request(params)
    if not res then
        httpc:close()
        return nil, err
    end

    local status = res.status
    if not status then
        httpc:close()
        return nil, "No status from consul"
    end

    local res_body, err = res:read_body()
    if not res_body then
        httpc:close()
        return nil, err
    end

    if DEBUG then
        ngx_log(ngx_DEBUG, "[Consul] Status: ", status)
        ngx_log(ngx_DEBUG, "[Consul] Headers:\n", require("cjson").encode(res.headers))
        ngx_log(ngx_DEBUG, "[Consul] Body:\n", res_body)
    end

    local headers = res.headers
    if headers["Content-Type"] == 'application/json' then
        res.body = safe_json_decode(res_body)
    else
        res.body = res_body
    end

    httpc:set_keepalive()

    return res
end


-- Parse Base64 encoded KV entries
local function _request_decoded(self, method, path, args, body)
    local res, err = _request(self, method, path, args, body)
    if not res then
        return nil, err
    end

    if res.body and type(res.body) == "table" then
        for _, entry in ipairs(res.body) do
            if type(entry.Value) == "string" then
                local decoded = ngx_decode_base64(entry.Value)
                if decoded ~= nil then
                    entry.Value = decoded
                    if DEBUG then ngx_log(ngx_DEBUG, "[Consul] Decoded entry:\n", decoded) end
                else
                    ngx_log(ngx_WARN, "[Consul] Could not decode Value")
                    if DEBUG then ngx_log(ngx_DEBUG, entry.Value) end
                end
            end
        end
    end

    return res, err
end


-- Method functions
function _M.get(self, path, args)
    if not path or type(path) ~= "string" then
        return nil, "Path (string) required"
    end
    return _request(self, "GET", path, args)
end


function _M.put(self, path, body, args) -- Only PUT has a body
    if not path or not body or type(path) ~= "string" then
        return nil, "Path (string) and body required"
    end
    return _request(self, "PUT", path, args, body)
end


function _M.delete(self, path, args)
    if not path or type(path) ~= "string" then
        return nil, "Path (string) required"
    end
    return _request(self, "DELETE", path, args)
end


-- KV Helper functions
-- Prepend /kv and automaticlaly base64 decode responses
function _M.put_key(self, key, value, args)
    if not key or not value or type(key) ~= "string" then
        return nil, "Key (string) and value required"
    end
    local path = "/kv/"..key
    return _request(self, "PUT", path, args, value)
end


function _M.get_key(self, key, args)
    if not key or type(key) ~= "string" then
        return nil, "Key (string) required"
    end
    local path = "/kv/"..key
    return _request_decoded(self, "GET", path, args)
end


function _M.list_keys(self, prefix, args)
    prefix = prefix or ""
    if type(prefix) ~= "string" then
        return nil, "non-string prefix"
    end

    args = args or {}
    args['keys'] = true -- ensure keys param is passed

    local path = "/kv/"..prefix
    return _request(self, "GET", path, args)
end


function _M.delete_key(self, key, args)
    if not key or type(key) ~= "string" then
        return nil, "Key (string) required"
    end
    local path = "/kv/"..key
    return _request(self, "DELETE", path, args)
end


-- TXN helper
-- Takes a table of transactions (https://www.consul.io/api/txn.html)
-- set Values will be automatically base64 encoded
-- or a JSON string of transactions (no automatic encoding)
-- Returns base64 decoded entries
function _M.txn(self, payload, args)
    if not payload then
        return nil, "Payload required"
    end

    if type(payload) == "table" then
        for _, el in ipairs(payload) do
            if el.KV then
                local val_type = type(el.KV.Value)

                if val_type  == "string" or val_type == "number" or val_type == "boolean" then
                    if val_type == "boolean" then
                        el.KV.Value = tostring(el.KV.Value)
                    end

                    if DEBUG then ngx_log(ngx_DEBUG, "[Consul txn] Encoding value:\n", el.KV.Value) end
                    el.KV.Value = ngx_encode_base64(el.KV.Value)
                end
            end
        end
    end

    local res, err = _request(self, "PUT", "/txn", args, payload)
    if not res then
        return nil, err
    end

    if res.body.Results and res.body.Results ~= ngx_null then
        for _, entry in ipairs(res.body.Results) do
            if type(entry.KV.Value) == "string" then
                local decoded = ngx_decode_base64(entry.KV.Value)
                if decoded ~= nil then
                    entry.KV.Value = decoded
                    if DEBUG then ngx_log(ngx_DEBUG, "[Consul txn] Decoded entry:\n", decoded) end
                else
                    ngx_log(ngx_WARN, "[Consul txn] Could not decode Value")
                    if DEBUG then ngx_log(ngx_DEBUG, entry.KV.Value) end
                end
            end
        end
    end

    return res, err
end


return _M
