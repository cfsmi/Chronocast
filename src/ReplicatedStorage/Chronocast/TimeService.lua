-- Every environment uses Roblox's shared server-time epoch, not module-load time.
local Workspace = game:GetService("Workspace")
local TimeService = {}

function TimeService.getServerTime()
	return Workspace:GetServerTimeNow()
end

function TimeService.isValidTime(time, historyDuration)
	local now = TimeService.getServerTime()
	return type(time) == "number" and time <= now and time >= now - historyDuration
end

return TimeService
