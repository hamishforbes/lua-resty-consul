
package = "lua-resty-consul"
version = "0.1-0"

source = {
  url = "git://github.com/hamishforbes/lua-resty-consul.git",
  tag = "v0.1",
}

description = {
  summary = "Library to interface with the consul HTTP API from ngx_lua",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
  "lua-resty-http",
}

build = {
  type = "builtin",
  modules = {
    ["resty.consul"] = "lib/resty/consul.lua",
  },
}