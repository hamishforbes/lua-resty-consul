use Test::Nginx::Socket 'no_plan';
use Cwd qw(cwd);

my $pwd = cwd();

$ENV{TEST_LEDGE_REDIS_DATABASE} ||= 1;
$ENV{TEST_NGINX_PORT} |= 1984;
$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
$ENV{TEST_NGINX_SOCKET_DIR} ||= $ENV{TEST_NGINX_HTML_DIR};

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_ssl_trusted_certificate "../html/rootca.pem";
    ssl_certificate "../html/example.com.crt";
    ssl_certificate_key "../html/example.com.key";

    init_by_lua_block {
        require("resty.consul")._debug(true)

        TEST_NGINX_PORT = $ENV{TEST_NGINX_PORT}
        TEST_NGINX_SSL_SOCK = "unix:$ENV{TEST_NGINX_SOCKET_DIR}/nginx-ssl.sock"
    }
};

$ENV{TEST_NGINX_SOCKET_DIR} ||= $ENV{TEST_NGINX_HTML_DIR};

sub read_file {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $RootCACert = read_file("t/cert/rootCA.pem");
our $ExampleCert = read_file("t/cert/example.com.crt");
our $ExampleKey = read_file("t/cert/example.com.key");

no_long_string();
no_root_location();
run_tests();

__DATA__
=== TEST 1: HTTPS Request
--- http_config eval
"$::HttpConfig"
--- config
    listen unix:$TEST_NGINX_SOCKET_DIR/nginx-ssl.sock ssl;
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({host = TEST_NGINX_SSL_SOCK, port = 0, ssl = true, ssl_verify = false})

            local res, err = c:get('/dummy/foobar')
            if not res then
                ngx.say(err)
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.print(res.body)
        }
    }
    location / {
        content_by_lua_block {
            if ngx.var.scheme == "https" then
                ngx.say("HTTPS OK")
            else
                ngx.say("HTTP")
            end
        }
    }
--- user_files eval
">>> rootca.pem
$::RootCACert
>>> example.com.key
$::ExampleKey
>>> example.com.crt
$::ExampleCert"
--- request
GET /a
--- no_error_log
[error]
--- response_body
HTTPS OK

=== TEST 2: HTTPS Request verified
--- http_config eval
"$::HttpConfig"
--- config
    listen unix:$TEST_NGINX_SOCKET_DIR/nginx-ssl.sock ssl;
    location /a {
        content_by_lua_block {
            local consul = require("resty.consul")
            c = consul:new({host = TEST_NGINX_SSL_SOCK, port = 0, ssl = true, ssl_verify = true, sni_host = "example.com"})

            local res, err = c:get('/dummy/foobar')
            if not res then
                ngx.say(err)
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.print(res.body)
        }
    }
    location / {
        content_by_lua_block {
            if ngx.var.scheme == "https" then
                ngx.say("HTTPS OK")
            else
                ngx.say("HTTP")
            end
        }
    }
--- user_files eval
">>> rootca.pem
$::RootCACert
>>> example.com.key
$::ExampleKey
>>> example.com.crt
$::ExampleCert"
--- request
GET /a
--- no_error_log
[error]
--- response_body
HTTPS OK
