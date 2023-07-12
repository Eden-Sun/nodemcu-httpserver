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
    if file.exists("app.lua") then
        dofile("app.lua")
    else
        print("app.lua deleted or renamed, it now nothing to do")
    end
end

function dd()
    file.remove("app.lua")
    print("app.lua deleted, restart to stop app")
end

print("WebMCU boot up, app will run in 3 seconds")
print('if app ran with bugs, just type file.remove("app.lua") or dd() to remove it')
print("Waiting...")

node.setcpufreq(node.CPU160MHZ)
tmr.create():alarm(3000, tmr.ALARM_SINGLE, startup)
