-- A timeline owns capture configuration, immutable snapshots, and collision history.
local RingBuffer = require(script.Parent.History.RingBuffer)
local Interpolation = require(script.Parent.History.Interpolation)
local Config = require(script.Parent.Config)
local TimeService = require(script.Parent.TimeService)
local Immutable = require(script.Parent.Immutable)

local Timeline = {}
Timeline.__index = Timeline

local function inferAdapter(instance)
	assert(typeof(instance) == "Instance", "Track requires an Adapter or an Instance for auto-inference")
	local root
	if instance:IsA("BasePart") then
		root = instance
	elseif instance:IsA("Model") then
		root = instance.PrimaryPart
		assert(root and root:IsDescendantOf(instance), "Auto-inferred Models require a stable PrimaryPart")
	else
		error("Cannot infer an adapter: Instance must be a BasePart or Model")
	end
	return {
		GetTransform = function()
			if instance:IsA("Model") then
				assert(instance.PrimaryPart == root, "Model PrimaryPart changed; untrack and retrack with a stable adapter")
				return instance:GetPivot()
			end
			return root.CFrame
		end,
		GetVelocity = function() return root.AssemblyLinearVelocity end,
		GetAngularVelocity = function() return root.AssemblyAngularVelocity end,
	}
end

function Timeline.new(config, globalConfig)
	assert(type(config.Id) == "string" and #config.Id > 0, "Timeline requires a nonempty string Id")
	local merged = Config.merge(globalConfig, config)
	local adapter = config.Adapter
	if adapter == nil then
		assert(merged.AutoInferAdapters, "An Adapter is required when AutoInferAdapters is disabled")
		adapter = inferAdapter(config.Instance)
	end
	assert(type(adapter) == "table" and type(adapter.GetTransform) == "function", "Adapter.GetTransform must be a function")
	local self = setmetatable({
		Id = config.Id,
		Config = merged,
		History = RingBuffer.new(Config.calculateBufferCapacity(merged.SnapshotRate, merged.HistoryDuration)),
		Adapter = adapter,
		Collision = config.Collision and Immutable.copyAndFreeze(config.Collision) or nil,
		Metadata = config.Metadata or adapter.Metadata or {},
		_lastSnapshotTime = nil,
		_destroyed = false,
		_onDestroy = nil,
	}, Timeline)
	return self
end

-- Internal scheduler hook. Capture a real current sample; never invent missed physics frames.
function Timeline:captureSnapshot(currentTime)
	if self._destroyed then return false end
	local time = currentTime or TimeService.getServerTime()
	assert(type(time) == "number" and time == time and math.abs(time) < math.huge, "Snapshot time must be finite")
	if self._lastSnapshotTime and time - self._lastSnapshotTime < self.Config.SnapshotRate then
		return false
	end
	local adapter = self.Adapter
	local transform = adapter:GetTransform(self, time)
	assert(typeof(transform) == "CFrame", "Adapter.GetTransform must return a CFrame")
	local velocity = adapter.GetVelocity and adapter:GetVelocity(self, time) or nil
	local angularVelocity = adapter.GetAngularVelocity and adapter:GetAngularVelocity(self, time) or nil
	assert(velocity == nil or typeof(velocity) == "Vector3", "Adapter.GetVelocity must return a Vector3 or nil")
	assert(angularVelocity == nil or typeof(angularVelocity) == "Vector3", "Adapter.GetAngularVelocity must return a Vector3 or nil")
	local metadata = {}
	for key, provider in pairs(self.Metadata) do
		if type(provider) == "function" then
			metadata[key] = provider(self, time)
		else
			metadata[key] = provider
		end
	end
	-- Adapters may yield. An untrack while yielding must not write into a destroyed buffer.
	if self._destroyed then return false end
	self.History:push({
		Time = time,
		Transform = transform,
		Velocity = velocity,
		AngularVelocity = angularVelocity,
		Metadata = metadata,
		Collision = self.Collision,
	})
	self._lastSnapshotTime = time
	return true
end

function Timeline:getState(time)
	if self._destroyed then return nil end
	local before, after = self.History:findBracketingSnapshots(time)
	if before == nil and after == nil then return nil end
	if before == nil then return Interpolation.snapshotToState(after) end
	if after == nil then
		-- Extrapolation is deliberately unsupported: historical queries use the nearest sample.
		return Interpolation.snapshotToState(before)
	end
	if before == after then return Interpolation.snapshotToState(before) end
	return Interpolation.snapshotToState(Interpolation.interpolate(before, after, time, self.Config.Interpolation))
end

function Timeline:getSnapshots()
	local snapshots = {}
	if not self._destroyed then
		for entry in self.History:entries() do table.insert(snapshots, entry) end
	end
	return table.freeze(snapshots)
end

-- A replacement affects future captures; existing snapshots keep their original shape.
function Timeline:setCollision(collisionDef)
	assert(not self._destroyed, "Timeline is destroyed")
	self.Collision = collisionDef and Immutable.copyAndFreeze(collisionDef) or nil
end

function Timeline:destroy()
	if self._destroyed then return end
	self._destroyed = true
	self.History:clear()
	self.Adapter = nil
	self.Collision = nil
	self.Metadata = nil
	local onDestroy = self._onDestroy
	self._onDestroy = nil
	if onDestroy then onDestroy(self) end
end

function Timeline:isDestroyed() return self._destroyed end
Timeline.GetState = Timeline.getState
Timeline.GetSnapshots = Timeline.getSnapshots
Timeline.SetCollision = Timeline.setCollision
Timeline.Destroy = Timeline.destroy
return Timeline
