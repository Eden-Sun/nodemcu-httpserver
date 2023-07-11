wifi_path = "wificonfig.lua"
host_name = 'webmcu'
web_port = '80'

local startServer = function(ip)
    if (dofile("__/server.lua")(web_port)) then
        print("webmct-httpserver running at:")
        print("   http://" .. ip .. ":" .. web_port)
        mdns.register(host_name, {
            description = 'webmcu',
            service = "http",
            port = web_port,
            location = 'global'
        })
        print('   http://' .. host_name .. '.local.:' .. web_port)

        print('LED is ON, try enter `gpio.write(ONBOARD_LED, gpio.LOW)` to turn it off')
    end
end

ONBOARD_LED = 0

local function wifi_start(wifi_config)
    print('try connect to ' .. wifi_config.ssid .. '...')
    wifi.setmode(wifi.STATION)
    wifi.sta.config(wifi_config)

    wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function(args)
        local ip = args["IP"]
        print("Connected to WiFi Access Point. Got IP: " .. args["IP"])

        gpio.mode(ONBOARD_LED, gpio.OUTPUT)
        gpio.write(ONBOARD_LED, gpio.LOW)
        startServer(ip)
        wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, function(args)
            print("Lost connectivity! Restarting...")
            node.restart()
        end)
    end)

    -- What if after a while (30 seconds) we didn't connect? Restart and keep trying.
    local watchdogTimer = tmr.create()
    local checks = 10
    watchdogTimer:register(3000, tmr.ALARM_AUTO, function(watchdogTimer)
        if checks == 0 then
            print("please check your wifi config with setwifi(ooo,xxx)")
            watchdogTimer:unregister()
            return
        end

        checks = checks - 1
        if wifi.sta.getip() ~= nil then
            watchdogTimer:unregister()
            collectgarbage()
            return
        end
        print("No IP yet, waiting...")

    end)
    watchdogTimer:interval(1000) -- actually, 3 seconds is better!
    watchdogTimer:start()
end

function setwifi(ssid, pwd)
    if file.open(wifi_path, "w+") then
        file.write('return { ssid="' .. ssid .. '", pwd="' .. pwd .. '" } \n')
        file.close()
    end
    print("wifi config set to " .. ssid .. " " .. pwd)
    wifi_start({
        ssid = ssid,
        pwd = pwd
    })
end

if not file.exists(wifi_path) then
    print("No config file found, please upload to wifi config")
    print('you can enter setwifi("abc", "123") to set wifi config')
else
    local success, config = pcall(dofile, wifi_path)
    wifi_start(config)
    config = nil
    collectgarbage()
end

