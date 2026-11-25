-- Chronocast v2 - Temporal Context
-- Contexts are immutable public handles with private mutable reconstruction caches.
--
-- A context pins registry membership at creation: timelines tracked afterwards are
-- invisible to it. The first access to a timeline's state or snapshots is cached for
-- the context's lifetime, so repeated reads and queries agree even as history rolls.
local Immutable = require(script.Parent.Immutable)

local Context = {}
local NIL_STATE = {}
local backing = setmetatable({}, { __mode = "k" })

local function contextData(self)
	return backing[self]
end

local function live(self)
	local data = contextData(self)
	if data and not data.Destroyed then
		return data
	end
	return nil
end

local contextMetatable = {
	__index = function(self, key)
		if key == "Time" then
			local data = contextData(self)
			return data and data.Time
		end
		return Context[key]
	end,
	__newindex = function()
		error("Context is immutable", 2)
	end,
}
table.freeze(contextMetatable)

function Context.new(time, registry)
	assert(type(time) == "number", "Context time must be a number")
	local self = setmetatable({}, contextMetatable)
	backing[self] = {
		Time = time,
		Registry = registry,
		Generation = registry and registry.generation and registry:generation() or math.huge,
		Cache = {},
		Snapshots = {},
		Destroyed = false,
	}
	if table.freeze then
		table.freeze(self)
	end
	return self
end

function Context:getState(timeline)
	local data = live(self)
	if not data or not timeline then
		return nil
	end
	local cached = data.Cache[timeline]
	if cached ~= nil then
		if cached == NIL_STATE then
			return nil
		end
		return cached
	end
	local state = timeline:getState(data.Time)
	if state ~= nil then
		state = Immutable.copyAndFreeze(state)
	end
	data.Cache[timeline] = state == nil and NIL_STATE or state
	return state
end

function Context:_getRegistry()
	local data = live(self)
	return data and data.Registry or nil
end

-- Internal query seam: Id-sorted timelines visible to this context whose history may
-- intersect the AABB. Timelines with cached state are always included so a cached
-- state cannot be filtered out after its snapshots have been evicted from the index.
function Context:_candidates(min, max)
	local data = live(self)
	if not data or not data.Registry then
		return {}
	end
	local generation = data.Generation
	local result, seen = {}, {}
	for _, timeline in ipairs(data.Registry:candidates(min, max)) do
		if (timeline._generation or 0) <= generation then
			seen[timeline] = true
			table.insert(result, timeline)
		end
	end
	local added = false
	for timeline, state in pairs(data.Cache) do
		if state ~= NIL_STATE and not seen[timeline] and (timeline._generation or 0) <= generation then
			table.insert(result, timeline)
			added = true
		end
	end
	if added then
		table.sort(result, function(a, b)
			return a.Id < b.Id
		end)
	end
	return result
end

function Context:getCollision(timeline)
	local state = self:getState(timeline)
	return state and state.Collision or nil
end

-- Snapshots recorded up to and including the context time, frozen on first access.
function Context:getSnapshots(timeline)
	local data = live(self)
	if not data or not timeline then
		return table.freeze({})
	end
	local cached = data.Snapshots[timeline]
	if cached then
		return cached
	end
	local snapshots = {}
	for _, snapshot in ipairs(timeline:getSnapshots()) do
		if snapshot.Time > data.Time then
			break
		end
		table.insert(snapshots, snapshot)
	end
	table.freeze(snapshots)
	data.Snapshots[timeline] = snapshots
	return snapshots
end

function Context:cast(params)
	assert(live(self), "Cannot Cast on a destroyed Context")
	assert(type(params) == "table", "Cast requires a parameter table")
	return require(script.Parent.Query).cast(self, params)
end

function Context:overlap(params)
	assert(live(self), "Cannot Overlap on a destroyed Context")
	assert(type(params) == "table", "Overlap requires a parameter table")
	return require(script.Parent.Query).overlap(self, params)
end

-- Deprecated: prefer Cast and Overlap. Kept with its original { Hit = false } miss shape.
function Context:query(params)
	if not live(self) then
		return { Hit = false }
	end
	assert(params.Shape, "Query requires a Shape")
	assert(params.Parameters, "Query requires Parameters")
	return require(script.Parent.Query).execute(self, params)
end

function Context:destroy()
	local data = contextData(self)
	if not data then
		return
	end
	data.Destroyed = true
	table.clear(data.Cache)
	table.clear(data.Snapshots)
	data.Registry = nil
end

function Context:isDestroyed()
	return live(self) == nil
end

function Context:cacheSize()
	local data = contextData(self)
	if not data then
		return 0
	end
	local count = 0
	for _ in pairs(data.Cache) do
		count += 1
	end
	return count
end

Context.Cast = Context.cast
Context.Overlap = Context.overlap
Context.Query = Context.query
Context.GetState = Context.getState
Context.GetCollision = Context.getCollision
Context.GetSnapshots = Context.getSnapshots
Context.Destroy = Context.destroy
Context.IsDestroyed = Context.isDestroyed
Context.CacheSize = Context.cacheSize

return Context
