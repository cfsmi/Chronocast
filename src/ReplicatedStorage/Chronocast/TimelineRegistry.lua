-- Chronocast v2 - Timeline Registry
--
-- Manages all tracked timelines.
-- Provides lookup by ID and iteration for spatial queries.

local TimelineRegistry = {}
TimelineRegistry.__index = TimelineRegistry

--- Creates a new TimelineRegistry.
--- @return table
function TimelineRegistry.new()
	local self = setmetatable({
		_timelines = {}, -- id -> Timeline
		_count = 0,
	}, TimelineRegistry)
	return self
end

--- Adds a timeline to the registry.
--- @param timeline table
function TimelineRegistry:add(timeline)
	assert(timeline.Id ~= nil, "Timeline must have an Id")
	assert(self._timelines[timeline.Id] == nil, "Timeline Id already registered: " .. tostring(timeline.Id))
	self._timelines[timeline.Id] = timeline
	self._count += 1
end

--- Removes a timeline from the registry by ID.
--- @param id string
function TimelineRegistry:remove(id)
	if self._timelines[id] then
		self._timelines[id] = nil
		self._count -= 1
	end
end

--- Returns a timeline by ID.
--- @param id string
--- @return table?
function TimelineRegistry:get(id)
	return self._timelines[id]
end

--- Returns all registered timelines.
--- @return { table }
function TimelineRegistry:getAll()
	local result = {}
	for _, timeline in pairs(self._timelines) do
		table.insert(result, timeline)
	end
	-- Stable ordering makes equal-distance query ties independent of hash iteration.
	table.sort(result, function(a, b) return a.Id < b.Id end)
	return result
end

--- Returns the number of registered timelines.
--- @return number
function TimelineRegistry:count()
	return self._count
end

--- Iterates over all timelines.
--- @return function iterator
function TimelineRegistry:entries()
	return pairs(self._timelines)
end

--- Clears all timelines from the registry.
function TimelineRegistry:clear()
	self._timelines = {}
	self._count = 0
end

return TimelineRegistry