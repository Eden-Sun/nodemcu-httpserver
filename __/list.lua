return function(connection, req, args)
    dofile("httpserver-header.lc")(connection, 200, 'json')
    connection:send('{')
    local remaining, used, total = file.fsinfo()
    local headerExist = 0
    connection:send('"files":{')

    for name, size in pairs(file.list()) do
        print(name, size)
        if (headerExist > 0) then
            connection:send(',')
        end

        local url = string.match(name, ".*/(.*)")
        url = name
        connection:send('"' .. url .. '":"' .. size .. '"')

        headerExist = 1
    end

    connection:send('},')

    connection:send('"total":"' .. total .. '",')
    connection:send('"used":"' .. used .. '",')
    connection:send('"free":"' .. remaining .. '"')
    connection:send('}')
    collectgarbage()
end
