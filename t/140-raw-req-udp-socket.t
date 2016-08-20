# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua::Dgram;

repeat_each(2);

plan tests => repeat_each() * 43;

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: sanity
--- dgram_server_config

    content_by_lua_block {
        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end

        local data, err = sock:receive(5)
        if not data then
            ngx.log(ngx.ERR, "server: failed to receive: ", err)
            return
        end

        local bytes, err = sock:send("1: received: " .. data .. "\n")
        if not bytes then
            ngx.log(ngx.ERR, "server: failed to send: ", err)
            return
        end
    }

--- dgram_request: hello
--- dgram_response
1: received: hello
--- no_error_log
stream lua socket tcp_nodelay
[error]



=== TEST 2: multiple raw req sockets
--- dgram_server_config
    content_by_lua_block {
        local sock, err = ngx.req.socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end
        local sock2, err = ngx.req.socket(true)
        if not sock2 then
            ngx.log(ngx.ERR, "server: failed to get raw req socket2: ", err)
            return
        end

    }

--- stap2
F(ngx_dgram_header_filter) {
    println("header filter")
}
F(ngx_dgram_lua_req_socket) {
    println("lua req socket")
}
--- dgram_response
--- error_log
server: failed to get raw req socket2: duplicate call



=== TEST 3: ngx.say after ngx.req.udp_socket(true)
--- dgram_server_config
    content_by_lua_block {
        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end
        local ok, err = ngx.say("ok")
        if not ok then
            ngx.log(ngx.ERR, "failed to say: ", err)
            return
        end
    }

--- dgram_response
ok
--- no_error_log
[error]



=== TEST 4: ngx.print after ngx.req.udp_socket(true)
--- dgram_server_config
    content_by_lua_block {
        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end
        local ok, err = ngx.print("ok")
        if not ok then
            ngx.log(ngx.ERR, "failed to print: ", err)
            return
        end
    }

--- dgram_response chomp
ok
--- no_error_log
[error]



=== TEST 5: ngx.eof after ngx.req.udp_socket(true)
--- dgram_server_config
    content_by_lua_block {
        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end
        local ok, err = ngx.eof()
        if not ok then
            ngx.log(ngx.ERR, "failed to eof: ", err)
            return
        end
    }

--- config
    server_tokens off;

--- dgram_response
--- no_error_log
[error]



=== TEST 6: ngx.flush after ngx.udp_req.socket(true)
--- dgram_server_config
    content_by_lua_block {
        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end
        local ok, err = ngx.flush()
        if not ok then
            ngx.log(ngx.ERR, "failed to flush: ", err)
            return
        end
    }

--- dgram_response
--- no_error_log
[error]



=== TEST 7: receive timeout
--- dgram_server_config
    content_by_lua_block {
        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end

        sock:settimeout(100)

        local data, err, partial = sock:receive(10)
        if not data then
            ngx.log(ngx.ERR, "server: 1: failed to receive: ", err, ", received: ", partial)
        end

        data, err, partial = sock:receive(10)
        if not data then
            ngx.log(ngx.ERR, "server: 2: failed to receive: ", err, ", received: ", partial)
        end

        ngx.exit(444)
    }

--- dgram_request chomp
ab
--- dgram_response
--- wait: 0.1
--- error_log
stream lua tcp socket read timed out
server: 1: failed to receive: timeout, received: ab while
server: 2: failed to receive: timeout, received:  while
--- no_error_log
[alert]



=== TEST 8: on_abort called during ngx.sleep()
--- dgram_server_config
    lua_check_client_abort on;

    content_by_lua_block {
        local ok, err = ngx.on_abort(function (premature)
            ngx.log(ngx.WARN, "mysock handler aborted") end)
        if not ok then
            ngx.log(ngx.ERR, "failed to set on_abort handler: ", err)
            return
        end

        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end

        local data, err = sock:receive(5)
        if not data then
            ngx.log(ngx.ERR, "server: failed to receive: ", err)
            return
        end

        print("msg received: ", data)

        local bytes, err = sock:send("1: received: " .. data .. "\n")
        if not bytes then
            ngx.log(ngx.ERR, "server: failed to send: ", err)
            return
        end

        ngx.sleep(1)
    }

--- dgram_request chomp
hello
--- dgram_response
receive stream response error: timeout
--- abort
--- timeout: 0.2
--- error_log
mysock handler aborted
msg received: hello
--- no_error_log
[error]
--- wait: 1.1



=== TEST 9: on_abort called during sock:receive()
--- dgram_server_config
    lua_check_client_abort on;

    content_by_lua_block {
        local ok, err = ngx.on_abort(function (premature) ngx.log(ngx.WARN, "mysock handler aborted") end)
        if not ok then
            ngx.log(ngx.ERR, "failed to set on_abort handler: ", err)
            return
        end

        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end

        local data, err = sock:receive(5)
        if not data then
            ngx.log(ngx.ERR, "server: failed to receive: ", err)
            return
        end

        print("msg received: ", data)

        local bytes, err = sock:send("1: received: " .. data .. "\n")
        if not bytes then
            ngx.log(ngx.ERR, "server: failed to send: ", err)
            return
        end

        local data, err = sock:receive()
        if not data then
            ngx.log(ngx.WARN, "failed to receive a line: ", err)
            return
        end
    }

--- dgram_response
receive stream response error: timeout
--- timeout: 0.2
--- abort
--- error_log
server: failed to receive: client aborted
--- wait: 0.1



=== TEST 10: request body not read yet
--- dgram_server_config
    content_by_lua_block {
        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
            return
        end

        local data, err = sock:receive(5)
        if not data then
            ngx.log(ngx.ERR, "failed to receive: ", err)
            return
        end

        local ok, err = sock:send("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n" .. data)
        if not ok then
            ngx.log(ngx.ERR, "failed to send: ", err)
            return
        end
    }

--- dgram_request
hello
--- dgram_response eval
"HTTP/1.1 200 OK\r
Content-Length: 5\r
\r
hello"

--- no_error_log
[error]



=== TEST 11: read chunked request body with raw req socket
--- dgram_server_config
    content_by_lua_block {
        local sock, err = ngx.req.udp_socket(true)
        if not sock then
            ngx.log(ngx.ERR, "failed to new: ", err)
            return
        end
        local function myerr(...)
            ngx.log(ngx.ERR, ...)
            return ngx.exit(400)
        end
        local num = tonumber
        local MAX_CHUNKS = 1000
        local eof = false
        local chunks = {}
        for i = 1, MAX_CHUNKS do
            local line, err = sock:receive()
            if not line then
                myerr("failed to receive chunk size: ", err)
            end

            local size = num(line, 16)
            if not size then
                myerr("bad chunk size: ", line)
            end

            if size == 0 then -- last chunk
                -- receive the last line
                line, err = sock:receive()
                if not line then
                    myerr("failed to receive last chunk: ", err)
                end

                if line ~= "" then
                    myerr("bad last chunk: ", line)
                end

                eof = true
                break
            end

            local chunk, err = sock:receive(size)
            if not chunk then
                myerr("failed to receive chunk of size ", size, ": ", err)
            end

            local data, err = sock:receive(2)
            if not data then
                myerr("failed to receive chunk terminator: ", err)
            end

            if data ~= "\r\n" then
                myerr("bad chunk terminator: ", data)
            end

            chunks[i] = chunk
        end

        if not eof then
            myerr("too many chunks (more than ", MAX_CHUNKS, ")")
        end

        local concat = table.concat
        local body = concat{"got ", #chunks, " chunks.\nrequest body: "}
                     .. concat(chunks) .. "\n"
        local ok, err = sock:send(body)
        if not ok then
            myerr("failed to send response: ", err)
        end
    }

--- config
--- dgram_request eval
"5\r
hey, \r
b\r
hello world\r
0\r
\r
"
--- dgram_response
got 2 chunks.
request body: hey, hello world

--- no_error_log
[error]
[alert]