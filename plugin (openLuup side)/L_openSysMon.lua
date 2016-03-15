_NAME = "openSysMon"
_VERSION = "2016.03.14"
_DESCRIPTION = "System monitor plugin for openLuup!!"
_AUTHOR = "logread (aka LV999)"

--[[

		Version 0.3 (beta)
		changelog: cleanup of code

		plugin files (c) Chris Jackson, except this program (L_openSysMon.lua")

		Special thanks to akbooer for his advise and for developing the openLuup environement

This plug-in is intended to run under the "openLuup" emulation of a Vera system
and display/monitor system information about the partner Vera on same LAN

It should work on a "real" Vera, but there is no point to it

It is intended to work in hand with a companion lua module (SysMonModule.lua) to be installed
on the Vera to be monitored (see installation document)

This program is free software: you can redistribute it and/or modify
it under the condition that it is for private or home useage and
this whole comment is reproduced in the source code file.
Commercial utilisation is not authorized without the appropriate
written agreement from "logread", contact by PM on http://forum.micasaverde.com/
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
--]]

local this_device
local SID_SM = "urn:cd-jackson-com:serviceId:SystemMonitor"

function SysMonHandler(lul_request, lul_parameters, lul_outputformat)
	-- we are hopefully reading from our companion module !!! to do: error handling if incorrect call
	for key, value in pairs(lul_parameters) do
		luup.variable_set(SID_SM, key, value, this_device)
	end
	return "openSysMon variables received OK", "text/plain"
end

function sethandler() -- seems registering our handler from init() does not work
	luup.register_handler("SysMonHandler", "SysMon")
end

function init(lul_device)
	this_device = lul_device
	sethandler()
	return true, "OK", _NAME
end

-- do not delete
