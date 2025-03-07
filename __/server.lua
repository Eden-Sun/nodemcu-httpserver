-- httpserver
-- Author: Marcos Kirsch
-- Starts web server in the specified port.
return function(port)

    local s = net.createServer(net.TCP, 10) -- 10 seconds client timeout
    s:listen(port, function(connection)

        -- This variable holds the thread (actually a Lua coroutine) used for sending data back to the user.
        -- We do it in a separate thread because we need to send in little chunks and wait for the onSent event
        -- before we can send more, or we risk overflowing the mcu's buffer.
        local connectionThread
        local fileInfo

        local allowStatic = {
            GET = true,
            HEAD = true,

            POST = false,
            PUT = false,
            DELETE = false,
            TRACE = false,
            OPTIONS = false,
            CONNECT = false,
            PATCH = false
        }

        -- Pretty log function.
        local function log(connection, msg, optionalMsg)
            local port, ip = connection:getpeer()
            -- print(ip .. ":" .. port, msg, optionalMsg or "")
            print(ip .. ":" .. port, msg, optionalMsg or "", node.heap())
        end

        local function startServingStatic(connection, req, args)
            fileInfo = dofile("__/static.lua")(connection, req, args)
        end

        local function startServing(fileServeFunction, connection, req, args)
            connectionThread = coroutine.create(function(fileServeFunction, bufferedConnection, req, args)
                fileServeFunction(bufferedConnection, req, args)
                -- The bufferedConnection may still hold some data that hasn't been sent. Flush it before closing.
                if not bufferedConnection:flush() then
                    log(connection, "closing connection", "no (more) data")
                    connection:close()
                    connectionThread = nil
                    collectgarbage()
                end -- if not bufferedConnection:flush()
            end) -- coroutine.create

            local BufferedConnectionClass = dofile("httpserver-connection.lc")
            local bufferedConnection = BufferedConnectionClass:new(connection)
            BufferedConnectionClass = nil
            local status, err = coroutine.resume(connectionThread, fileServeFunction, bufferedConnection, req, args)
            if not status then
                log(connection, "Error: " .. err)
                log(connection, "closing connection", "error")
                connection:close()
                connectionThread = nil
                collectgarbage()
            end
        end

        local function handleRequest(connection, req, handleError)
            collectgarbage()
            local uri = req.uri
            local method = req.method

            -- WIP POST
            -- if method == 'POST' then
            --     method = ''
            --     startServing()
            --     url = nil
            --     req = nil
            -- end

            if #(uri.file) > 32 then
                -- nodemcu-firmware cannot handle long filenames.

                dofile("httpserver-error.lc")(connection, req, {
                    code = 414,
                    errorString = "Request-URI Too Long",
                    logFunction = log
                })

                -- startServing(dofile("httpserver-error.lc"), connection, req, {
                --     code = 400,
                --     errorString = "Bad Request",
                --     logFunction = log
                -- })
                url = nil
                req = nil
                return
            end

            local fileStat = file.stat(uri.file)

            -- handle ooo.xxx.gz

            if fileStat == nil then
                local gzStat = file.stat(uri.file .. ".gz")
                if gzStat == nil then
                    startServing(dofile("httpserver-error.lc"), connection, req, {
                        code = 404,
                        errorString = "Not Found",
                        logFunction = log
                    })
                    url = nil
                    req = nil
                else
                    startServingStatic(connection, req, {
                        ext = uri.ext,
                        file = uri.file .. ".gz",
                        total = gzStat.size,
                        isGzipped = true
                    })
                end
                gzStat = nil
                req = nil
                url = nil
                return
            end

            -- do not excute .lua
            if uri.isScript then
                -- fileServeFunction = dofile(uri.file)
                -- startServing(fileServeFunction, connection, req, uri.args)
                dofile(uri.file)(connection, req, uri.args)
                url = nil
                req = nil
                return
            end
            startServingStatic(connection, req, {
                ext = uri.ext,
                file = uri.file,
                total = fileStat.size
            })
            url = nil
            req = nil
        end

        local function onReceive(connection, payload)
            --            collectgarbage()
            -- as suggest by anyn99 (https://github.com/marcoskirsch/nodemcu-httpserver/issues/36#issuecomment-167442461)
            -- Some browsers send the POST data in multiple chunks.
            -- Collect data packets until the size of HTTP body meets the Content-Length stated in header
            if payload:find("Content%-Length:") or bBodyMissing then
                if fullPayload then
                    fullPayload = fullPayload .. payload
                else
                    fullPayload = payload
                end
                if (tonumber(string.match(fullPayload, "%d+", fullPayload:find("Content%-Length:") + 16)) >
                    #fullPayload:sub(fullPayload:find("\r\n\r\n", 1, true) + 4, #fullPayload)) then
                    bBodyMissing = true
                    return
                else
                    -- print("HTTP packet assembled! size: "..#fullPayload)
                    payload = fullPayload
                    fullPayload, bBodyMissing = nil
                end
            end
            collectgarbage()

            -- parse payload and decide what to serve.
            local req = dofile("httpserver-request.lc")(payload)
            log(connection, req.method, req.request)

            if (req.method == "GET" or req.method == "POST" or req.method == "PUT") then
                handleRequest(connection, req, handleError)
            else
                -- other methods
                local args = {}
                local fileServeFunction = dofile("httpserver-error.lc")
                if req.methodIsValid then
                    args = {
                        code = 501,
                        errorString = "Not Implemented",
                        logFunction = log
                    }
                else
                    args = {
                        code = 400,
                        errorString = "Bad Request",
                        logFunction = log
                    }
                end
                startServing(fileServeFunction, connection, req, args)
            end
        end

        local function onSent(connection, payload)
            collectgarbage()
            if connectionThread then
                local connectionThreadStatus = coroutine.status(connectionThread)
                if connectionThreadStatus == "suspended" then
                    -- Not finished sending file, resume.
                    local status, err = coroutine.resume(connectionThread)
                    if not status then
                        log(connection, "Error: " .. err)
                        log(connection, "closing connection", "error")
                        connection:close()
                        connectionThread = nil
                        collectgarbage()
                    end
                elseif connectionThreadStatus == "dead" then
                    -- We're done sending file.
                    log(connection, "closing connection", "thread is done")
                    connection:close()
                    connectionThread = nil
                    collectgarbage()
                end
            elseif fileInfo then
                local fileSize = fileInfo.total
                local chunkSize = 512
                -- Chunks larger than 1024 don't work.
                -- https://github.com/nodemcu/nodemcu-firmware/issues/1075
                local fileHandle = file.open(fileInfo.file)
                if fileSize > fileInfo.sent then
                    fileHandle:seek("set", fileInfo.sent)
                    local chunk = fileHandle:read(chunkSize)
                    fileHandle:close()
                    fileHandle = nil
                    fileInfo.sent = fileInfo.sent + #chunk
                    print(fileInfo.file .. ": Sent " .. #chunk .. " bytes, " .. fileSize - fileInfo.sent .. " to go.")
                    connection:send(chunk)
                    chunk = nil
                else
                    log(connection, "closing connetion", "Finished sending: " .. fileInfo.file)
                    connection:close()
                end
                fileSize = nil
                collectgarbage()
            else
                -- other case sent
                -- e.g http error
                log(connection, "closing connection", "no thread or file")
                connection:close()
                collectgarbage()
            end
        end

        local function onDisconnect(connection, payload)
            -- this should rather be a log call, but log is not available here
            --            print("disconnected")
            if connectionThread then
                connectionThread = nil
                collectgarbage()
            end
            if fileInfo then
                fileInfo = nil
                collectgarbage()
            end
        end

        connection:on("receive", onReceive)
        connection:on("sent", onSent)
        connection:on("disconnection", onDisconnect)

    end)
    return s

end
