-- check/flash/use LFS support, if possible
if node.getpartitiontable().lfs_size > 0 then
    if file.exists("lfs.img") then
        if file.exists("lfs_lock") then
            file.remove("lfs_lock")
            file.remove("lfs.img")
        else
            local f = file.open("lfs_lock", "w")
            f:flush()
            f:close()
            file.remove("httpserver-compile.lua")
            node.LFS.reload("lfs.img")
        end
    end
    pcall(node.flashindex("_init"))
end

-- Compile freshly uploaded nodemcu-httpserver lua files.
-- if file.exists("httpserver-compile.lua") then
-- dofile("httpserver-compile.lua")
-- file.remove("httpserver-compile.lua")
-- end

function startup()
    if file.exists("app.lua") ~= nil then
        print("app.lua deleted or renamed, it now nothing to do")
        return
    end

    dofile("app.lua")
end

print("WebMCU boot up, app will run in 3 seconds")
print("if app ran with bugs, just call file.remove(\"app.lua\") to remove it")
print("Waiting...")

tmr.create():alarm(3000, tmr.ALARM_SINGLE, startup)

if file.exists("config") == nil then
    print("No config file found, please upload to wifi config")
    file.remove("httpserver-compile.lua")
end

-- Set up NodeMCU's WiFi
dofile("httpserver-wifi.lc")

-- Start nodemcu-httpsertver
dofile("httpserver-init.lc")
