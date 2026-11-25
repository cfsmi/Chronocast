-- Callable ModuleScript test suite. Invoke the returned function in Studio.
return function()
	local Chronocast = game.ReplicatedStorage.Chronocast
	local Immutable = require(Chronocast.Immutable)
	local Config = require(Chronocast.Config)
	local Context = require(Chronocast.Context)
	local RingBuffer = require(Chronocast.History.RingBuffer)
	local Interpolation = require(Chronocast.History.Interpolation)

	local function expectError(callback, message)
		local ok = pcall(callback)
		assert(not ok, message)
	end

	-- Immutable graphs retain shared identity and cycles without retaining input tables.
	local shared = { Value = 1 }
	local source = { Left = shared, Right = shared }
	source.Self = source
	local snapshot = Immutable.copyAndFreeze(source)
	assert(snapshot ~= source and snapshot.Self == snapshot)
	assert(snapshot.Left == snapshot.Right and snapshot.Left ~= shared)
	assert(table.isfrozen(snapshot) and table.isfrozen(snapshot.Left))
	expectError(function() snapshot.Left.Value = 2 end, "nested snapshot table should be frozen")
	expectError(function() Immutable.copyAndFreeze(setmetatable({}, {})) end, "metatable tables should be rejected")
	expectError(function() Immutable.copyAndFreeze({ Mutable = Instance.new("Folder") }) end, "Instances should be rejected")

	-- Config layers are deeply independent and nested overrides do not mutate defaults.
	local globalOverrides = { Interpolation = { PositionMode = "Nearest" }, SpatialIndex = { CellSize = 12 } }
	local global = Config.create(globalOverrides)
	local timelineOverrides = { Interpolation = { RotationMode = "Linear" } }
	local merged = Config.merge(global, timelineOverrides)
	merged.Interpolation.PositionMode = "Changed"
	merged.SpatialIndex.CellSize = 99
	assert(global.Interpolation.PositionMode == "Nearest" and global.SpatialIndex.CellSize == 12)
	assert(timelineOverrides.Interpolation.RotationMode == "Linear")
	assert(Config.create().Interpolation.PositionMode == "Linear")
	assert(Config.merge(global, { SnapshotRate = 0.1 }).SnapshotRate == 0.1)
	expectError(function() Config.create({ SnapshotRate = 0 }) end, "nonpositive snapshot rate should be rejected")
	expectError(function() Config.merge(global, { HistoryDuration = math.huge }) end, "infinite history duration should be rejected")
	expectError(function() Config.merge(global, { Interpolation = { Extrapolate = true } }) end,
		"unsupported extrapolation should be rejected")
	local opaqueAdapter = function() end
	local copiedConfig = Config.create({ Adapter = opaqueAdapter })
	assert(copiedConfig.Adapter == opaqueAdapter)

	-- RingBuffer owns immutable copies; duplicate times replace the previous sample.
	expectError(function() RingBuffer.new(1.5) end, "fractional capacity should be rejected")
	local ring = RingBuffer.new(3)
	local input = { Time = 1, Metadata = { Value = 10 } }
	ring:push(input)
	input.Metadata.Value = 20
	assert(ring:newest().Metadata.Value == 10)
	ring:push({ Time = 2, Metadata = { Value = 20 } })
	ring:push({ Time = 1, Metadata = { Value = 30 } })
	assert(ring:count() == 2 and ring:oldest().Time == 1 and ring:newest().Time == 2)
	assert(ring:oldest().Metadata.Value == 30 and table.isfrozen(ring:oldest().Metadata))
	expectError(function() ring:push({ Time = math.huge }) end, "infinite snapshot time should be rejected")
	local eviction = RingBuffer.new(2)
	eviction:push({ Time = 1 })
	eviction:push({ Time = 2 })
	eviction:push({ Time = 1, Latest = true })
	eviction:push({ Time = 3 }) -- evicts timestamp 1 and its index entry
	expectError(function() eviction:push({ Time = 1 }) end, "evicted timestamps must not retain an index slot")
	expectError(function() eviction:push({ Time = 2.5 }) end, "new out-of-order timestamps must be rejected")
	assert(eviction:count() == 2 and eviction:oldest().Time == 2 and eviction:newest().Time == 3)
	eviction:push({ Time = 4 })
	assert(eviction:oldest().Time == 3 and eviction:newest().Time == 4)

	-- Collision is a sampled state property: interpolation uses the preceding snapshot.
	local collisionA = { Shape = "Box", Size = Vector3.new(1, 1, 1) }
	local collisionB = { Shape = "Sphere", Radius = 2 }
	local first = { Time = 1, Transform = CFrame.new(), Metadata = {}, Collision = collisionA }
	local second = { Time = 2, Transform = CFrame.new(2, 0, 0), Metadata = {}, Collision = collisionB }
	local interpolated = Interpolation.interpolate(first, second, 1.5, {})
	assert(interpolated.Collision == collisionA)
	local reconstructed = Interpolation.snapshotToState(second)
	assert(reconstructed.Collision ~= collisionB and reconstructed.Collision.Shape == collisionB.Shape)
	assert(table.isfrozen(reconstructed) and table.isfrozen(reconstructed.Transform))
	assert(table.isfrozen(reconstructed.Motion) and table.isfrozen(reconstructed.Metadata))
	expectError(function() reconstructed.Transform.Position = Vector3.zero end, "state transform should be frozen")

	-- Context public state is frozen, while cache entries (including nil) are private.
	local calls = 0
	local timeline = {
		Id = "identity-is-not-the-cache-key",
		getState = function(_, time)
			calls += 1
			if time == 4 then
				return { Time = time, Collision = collisionA }
			end
			return nil
		end,
		getSnapshots = function() return {} end,
	}
	local registry = {}
	local context = Context.new(4, registry)
	assert(context.Time == 4 and table.isfrozen(context) and context:_getRegistry() == registry)
	expectError(function() context.Time = 5 end, "Context.Time should be immutable")
	local contextCollision = context:getCollision(timeline)
	assert(contextCollision ~= collisionA and contextCollision.Shape == collisionA.Shape)
	assert(table.isfrozen(contextCollision))
	local cachedState = context:GetState(timeline)
	assert(cachedState.Collision == contextCollision and table.isfrozen(cachedState))
	expectError(function() cachedState.Collision.Shape = "Sphere" end, "Context state should be frozen")
	assert(calls == 1)
	local emptyTimeline = { getState = function() calls += 1; return nil end }
	assert(context:getState(emptyTimeline) == nil and context:getState(emptyTimeline) == nil)
	assert(calls == 2 and context:cacheSize() == 2)
	context:destroy()
	assert(context:isDestroyed() and context:getState(timeline) == nil)

	return true
end
