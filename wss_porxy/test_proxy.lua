local server = "ws://127.0.0.1:8080"  -- Backend WebSocket server URL
local wb = require("resty.websocket.server")
local wb_client = require("resty.websocket.client")
local json = require("cjson.safe")

local function log_data(direction, data)
    ngx.log(ngx.INFO, string.format("[%s] %s", direction, data))
end

local function proxy_websocket()
    -- Initialize WebSocket server
    local client, err = wb:new {
        timeout = 60000,  -- 5 seconds timeout
        max_payload_len = 65535
    }
    if not client then
        ngx.log(ngx.ERR, "Failed to create WebSocket: ", err)
        return ngx.exit(444)
    end

    -- Connect to the backend WebSocket server
    local backend, err = wb_client:new {
        timeout = 60000,
        max_payload_len = 65535
    }
    if not backend then
        ngx.log(ngx.ERR, "Failed to connect to backend WebSocket: ", err)
        client:send_close(1011, "Internal Server Error")
        return
    end

    local ok, err = backend:connect(server)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to backend server: ", err)
        client:send_close(1011, "Backend Server Unavailable")
        return
    end

    -- Proxy loop
    while true do
        -- Receive data from client
        local frame, typ, err = client:recv_frame()
        if not frame then
            ngx.log(ngx.ERR, "Failed to receive frame: ", err)
            break
	else
	    ngx.log(ngx.ERR, "client:recv_frame() OK: ")
	    ngx.log(ngx.ERR, frame)
	    ngx.log(ngx.ERR, typ)
	    ngx.log(ngx.ERR, err)
        end



        if typ == "close" then
            ngx.log(ngx.INFO, "Client closed connection")
            break
        elseif typ == "ping" then
            client:send_pong(frame)
        elseif typ == "pong" then
            ngx.log(ngx.INFO, "Received pong from client")
        elseif typ == "text" or typ == "binary" then
            log_data("Client -> Backend", frame)

            -- Modify data if needed
            -- frame = string.gsub(frame, "original", "modified")

            -- Block specific data
            if frame:find("BLOCK_THIS_DATA") then
                ngx.log(ngx.WARN, "Blocked client message")
                break
            end

            -- Send data to backend
            ok, err = backend:send_text(frame)
            if not ok then
                ngx.log(ngx.ERR, "Failed to send frame to backend: ", err)
                break
            end
        end

        -- Receive data from backend
        frame, typ, err = backend:recv_frame()
        if not frame then
            ngx.log(ngx.ERR, "Failed to receive frame from backend: ", err)
            break
        end

        if typ == "close" then
            ngx.log(ngx.INFO, "Backend closed connection")
            break
        elseif typ == "ping" then
            backend:send_pong(frame)
        elseif typ == "pong" then
            ngx.log(ngx.INFO, "Received pong from backend")
        elseif typ == "text" or typ == "binary" then
            log_data("Backend -> Client", frame)

            -- Modify data if needed
            -- frame = string.gsub(frame, "backend", "client")

            -- Send data to client
            ok, err = client:send_text(frame)
            if not ok then
                ngx.log(ngx.ERR, "Failed to send frame to client: ", err)
                break
            end
        end
    end

    -- Close connections
    client:send_close()
    backend:send_close()
end

return {
    handler = proxy_websocket
}
