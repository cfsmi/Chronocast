-- Chronocast v2 - Temporal Context
-- Contexts are immutable public handles with private mutable reconstruction caches.
local Immutable = require(script.Parent.Immutable)

local Context = {}
local NIL_STATE = {}
local backing = setmetatable({}, { __mode = "k" })

local function contextData(self)
	return backing[self]
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
		Cache = {},
		Destroyed = false,
	}
	if table.freeze then
		table.freeze(self)
	end
	return self
end

function Context:getState(timeline)
	local data = contextData(self)
	if not data or data.Destroyed or not timeline then
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
	local data = contextData(self)
	return data and not data.Destroyed and data.Registry or nil
end

function Context:getCollision(timeline)
	local state = self:getState(timeline)
	return state and state.Collision or nil
end

function Context:getSnapshots(timeline)
	local data = contextData(self)
	if not data or data.Destroyed or not timeline then
		return {}
	end
	return timeline:getSnapshots()
end

function Context:query(params)
	local data = contextData(self)
	if not data or data.Destroyed then
		return { Hit = false }
	end
	assert(params.Shape, "Query requires a Shape")
	assert(params.Parameters, "Query requires Parameters")
	local QueryEngine = require(script.Parent.Query)
	return QueryEngine.execute(self, params)
end

function Context:destroy()
	local data = contextData(self)
	if not data then
		return
	end
	data.Destroyed = true
	table.clear(data.Cache)
	data.Registry = nil
end

function Context:isDestroyed()
	local data = contextData(self)
	return data == nil or data.Destroyed
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

Context.Query = Context.query
Context.GetState = Context.getState
Context.GetCollision = Context.getCollision
Context.GetSnapshots = Context.getSnapshots
Context.Destroy = Context.destroy
Context.IsDestroyed = Context.isDestroyed
Context.CacheSize = Context.cacheSize

return Context
