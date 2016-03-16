module("SysMonModule", package.seeall)
--[[
	openSysMon module to run on Vera for openLuup openSysMon plugin
	written by logread (aka LV99)
	based on code from the SystemMonitor Plugin for Vera (c) Chris Jackson

	this module is the client side, to run in background on the host Vera to monitor
	while the server side is a plugin running on the openLuup machine (on same LAN for now!!!)
	server/client communication relies on a http GET from this module on the Vera to a handler on the openLuup machine

	Version 0.4
	changelog:
	- correction of bug in config() function
	- config(openLuupIP, SamplePeriod) MUST be called immediately after initialisation

--]]

-- User specific configuration parameters

local openLuupIP = "0.0.0.0" -- The IP of the machine running the openSysMon plugin, will be set by config()
local SamplePeriod = 300 -- 5 mins -- one single sample period in this version for simplicity

-- general parameters

local http = require("socket.http")

local variables = {}
local err
local lastUptime
local lastUptime
local uptimelogfilename = "/usr/uptime.log" -- this path/file needs to survive a reboot !!!
local serverpath = ""
local SYSMON_LOG_NAME = "SysMonModule: "
local configfilename = "/etc/cmh/cmh-ludl/openSysMon.conf"

-- local	SamplePeriodMem = 300	 -- 5 mins
-- local	SamplePeriodCPU = 300	 -- 5 mins
-- local	SamplePeriodUptime = 300 -- 5 mins

-- configure parameters for openLuupIP and/or SamplePeriod
function config(targetIP, period)
	if targetIP ~= nil then
		openLuupIP = targetIP -- no check if this is valid IP !!!
		serverpath = "http://" .. openLuupIP .. ":3480/data_request?id=lr_SysMon"
	end
	if period ~= nil then
		SamplePeriod = tonumber(period)
		if(SamplePeriod == nil) then SamplePeriod = 300 end
		if(SamplePeriod < 20) then SamplePeriod = 20
		elseif(SamplePeriod > 3600) then SamplePeriod = 3600 end
	end
	return openLuupIP, SamplePeriod
end

-- uptime log to local temp file that will survive a reboot
function saveuptime(uptime)
	local result
	local logfile = io.open(uptimelogfilename, "w")
	if logfile ~= nil then
		result = logfile:write(uptime)
		io.close(logfile)
	end
end

-- uptime read from temp file that survived the last reboot
function getuptime()
	local result
	local logfile = io.open(uptimelogfilename, "r")
	if logfile ~= nil then
		lastUptime = logfile:read("*number")
    	io.close(logfile)
	end
end

-- System poll Callback
function Poll_Data()

-- getMemory
	local memFree   = 0
	local memTotal  = 0
	local memCached = 0
	local line

	local fTmp=io.open("/proc/meminfo","r")
	if fTmp ~= nil then
		while true do
			line = fTmp:read("*line")

			if(line == nil) then
				io.close(fTmp)
				break
			end
--			luup.log(SYSMON_LOG_NAME .. line)

			words = {}
			for word in line:gmatch("%w+") do table.insert(words, word) end

			words[2] = tonumber(words[2])
			if(words[1] == "MemTotal") then
				memTotal = words[2]
				variables["memoryTotal"] = words[2]
			elseif(words[1] == "MemFree") then
				memFree = words[2]
				variables["memoryFree"] = words[2]
			elseif(words[1] == "Buffers") then
				variables["memoryBuffers"] = words[2]
			elseif(words[1] == "Cached") then
				memCached = words[2]
				variables["memoryCached"] = words[2]
			end
		end
	else
		luup.log(SYSMON_LOG_NAME .. "Error opening tmpfile during getMemory")
	end

	if(memTotal ~= 0) then
		variables["memoryUsed"] = memTotal - memFree
	end
	variables["memoryAvailable"] = memFree + memCached

-- getLoad()
	fTmp=io.open("/proc/loadavg","r")
	if fTmp ~= nil then
		line = fTmp:read("*line")
		io.close(fTmp)

		words = {}
		for word in line:gmatch("[^/ ]+") do table.insert(words, word) end

		variables["cpuLoad1"] =  	tonumber(words[1])
		variables["cpuLoad5"] =  	tonumber(words[2])
		variables["cpuLoad15"] =	tonumber(words[3])
		variables["procRunning"] =	tonumber(words[4])
		variables["procTotal"] =	tonumber(words[5])
	end

-- getUptime
	fTmp=io.open("/proc/uptime","r")
	if(fTmp ~= nil)then
		line = fTmp:read("*line")
		io.close(fTmp)

		words = {}
		for word in line:gmatch("[^/ ]+") do table.insert(words, word) end

		saveuptime(tonumber(words[1])) -- saves to our log file that survives reboots
		variables["uptimeTotal"] =	tonumber(words[1])
		variables["uptimeIdle"] =	tonumber(words[2])

		if(lastUptime ~= 0) then
			if(lastUptime > tonumber(words[1])) then
				variables["systemVeraRestart"] = 1
				variables["systemVeraRestartUnix"] = os.time()
				variables["systemVeraRestartTime"] = os.date("%H:%M %a %d/%m") -- modif format date LV 23/10/15
			else
				variables["systemLuupRestart"] = 1
				variables["systemLuupRestartUnix"] = os.time()
				variables["systemLuupRestartTime"] = os.date("%H:%M %a %d/%m") -- modif format date LV 23/10/15
			end

			local fTmp=io.open("/etc/cmh/last_reboot","r")
			if(fTmp ~= nil) then
				line = fTmp:read("*line")
				io.close(fTmp)

				local num = tonumber(line)
				if(num ~= nil) then
					variables["cmhLastRebootUnix"] = num
					variables["cmhLastRebootTime"] = os.date("%H:%M %a %d/%m", num) -- modif format date LV 23/10/15
				end
			end
		else
			variables["systemVeraRestart"] = 0
			variables["systemLuupRestart"] = 0
		end
		lastUptime = 0
	end
	variables["lastSampleTime"] = os.time() -- this timestamp did not exist in the original plugin
											-- added to allow a check on when the last refresh was

-- prepare the url (path of handler + parameters) string to be used for the http GET request
	local url = serverpath
	for key, value in pairs(variables) do
		url = url .. "&" .. key .. "=" .. tostring(value)
	end
	luup.log(SYSMON_LOG_NAME .. "calling " .. url) -- for debug
	local returndata, retcode = http.request(url)
	if returndata == nil then returndata = "" end -- avoid a crash in logging returndata if error in request
	luup.log(SYSMON_LOG_NAME .. retcode .. " " .. returndata) -- for debug
	local err = (retcode ~=200)
	if err then -- something wrong happpened (website down, wrong key or location)
		luup.log(SYSMON_LOG_NAME .. "bad response from openLuup") -- for debug
	else
		luup.log(SYSMON_LOG_NAME .. "good response from openLuup") -- for debug
	end
	luup.call_delay("Poll_Data", SamplePeriod) -- poll loop
end

-- Run once at module load
function init()
	luup.log(SYSMON_LOG_NAME.."Initialising module")

	-- Get the sample period
	if(SamplePeriod == nil) then SamplePeriod = 300 end
	if(SamplePeriod < 20) then SamplePeriod = 20
	elseif(SamplePeriod > 3600) then SamplePeriod = 3600 end
	variables["SamplePeriodCPU"] = SamplePeriod		-- maintain compatibility with the original plugin
	variables["SamplePeriodMem"] = SamplePeriod		-- maintain compatibility with the original plugin
	variables["SamplePeriodUptime"] = SamplePeriod 	-- maintain compatibility with the original plugin

	-- get the last uptime so we can detect restarts
	getuptime()
	if(lastUptime == nil) then lastUptime = 0 end

	-- register call back timer in the Lua global environment
	-- since luup.call_delay otherwise fails in a module (see http://forum.micasaverde.com/index.php?topic=10258.0)
	_G["Poll_Data"] = Poll_Data
	luup.call_delay("Poll_Data", 20) 	-- delay first poll by 20 seconds to allow for Vera to stabilize after startup
										-- as well as allow a call to the config() function from the Luup startup code
	luup.log(SYSMON_LOG_NAME .. "Startup complete")
end

init()

-- keep this line as the last one of the module (needs CR)
