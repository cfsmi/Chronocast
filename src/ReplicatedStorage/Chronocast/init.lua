-- Chronocast: reconstruct the past, then answer questions about it.
local RunService = game:GetService("RunService")
local Config = require(script.Config)
local TimeService = require(script.TimeService)
local Timeline = require(script.Timeline)
local Registry = require(script.TimelineRegistry)
local Context = require(script.Context)
local Chronocast = {}
local globalConfig = Config.create()
local registry = Registry.new()
local heartbeat = nil

local function stopWhenEmpty()
	if registry:count() == 0 and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function startScheduler()
	if heartbeat then return end
	heartbeat = RunService.Heartbeat:Connect(function()
		if not RunService:IsRunning() then return end
		local time = TimeService.getServerTime()
		for _, timeline in ipairs(registry:getAll()) do
			if not timeline._capturing then
				timeline._capturing = true
				local ok, err = pcall(timeline.captureSnapshot, timeline, time)
				timeline._capturing = false
				if not ok then
					-- Stop repeated failures without preventing healthy timelines from capturing.
					warn("Chronocast: untracking " .. timeline.Id .. " after capture failure: " .. tostring(err))
					timeline:destroy()
				end
			end
		end
	end)
end

function Chronocast:Track(config)
	assert(type(config) == "table", "Track requires a config table")
	assert(type(config.Id) == "string" and #config.Id > 0, "Track requires a nonempty string Id")
	assert(registry:get(config.Id) == nil, "Timeline Id already tracked: " .. config.Id)
	local timeline = Timeline.new(config, globalConfig)
	-- Fail before registration if the first adapter read or metadata validation fails.
	timeline:captureSnapshot()
	assert(registry:get(config.Id) == nil, "Timeline Id registered while adapter was yielding: " .. config.Id)
	registry:add(timeline)
	timeline._onDestroy = function(destroyed)
		if registry:get(destroyed.Id) == destroyed then registry:remove(destroyed.Id) end
		stopWhenEmpty()
	end
	startScheduler()
	return timeline
end

function Chronocast:Untrack(id)
	assert(type(id) == "string", "Untrack requires a string Id")
	local timeline = registry:get(id)
	if timeline then timeline:destroy() end
end

function Chronocast:CreateContext(time)
	assert(type(time) == "number" and time == time and math.abs(time) < math.huge, "Context time must be finite")
	return Context.new(time, registry)
end

function Chronocast:Query(params)
	assert(type(params) == "table", "Query requires a parameter table")
	local context = self:CreateContext(params.Time)
	local ok, result = pcall(context.Query, context, params)
	context:Destroy()
	if not ok then error(result, 2) end
	return result
end

function Chronocast:GetServerTime() return TimeService.getServerTime() end
Chronocast.Collision = require(script.Collision)
Chronocast.Path = require(script.Path)
Chronocast.Config = globalConfig
Chronocast.Types = require(script.Types)
return Chronocast
