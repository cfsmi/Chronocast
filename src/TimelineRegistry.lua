-- Chronocast v2 - Timeline Registry
--
-- Manages all tracked timelines.
-- Provides lookup by ID, a cached Id-sorted view, and spatial candidates.

local TimelineRegistry = {}
TimelineRegistry.__index = TimelineRegistry

--- Creates a new TimelineRegistry.
--- @param index table? - Optional SpatialIndex kept in sync with registered history
--- @return table
function TimelineRegistry.new(index)
	local self = setmetatable({
		_timelines = {}, -- id -> Timeline
		_count = 0,
		_sorted = nil, -- frozen Id-sorted array, rebuilt lazily after membership changes
		_generation = 0, -- increments on every add; contexts pin membership by generation
		_index = index,
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
	self._generation += 1
	timeline._generation = self._generation
	self._sorted = nil
	if self._index then
		timeline._index = self._index
		for snapshot in timeline.History:entries() do
			self._index:addSample(timeline, snapshot)
		end
	end
end

--- Removes a timeline from the registry by ID.
--- @param id string
function TimelineRegistry:remove(id)
	local timeline = self._timelines[id]
	if timeline then
		self._timelines[id] = nil
		self._count -= 1
		self._sorted = nil
		if self._index then
			self._index:removeTimeline(timeline)
			timeline._index = nil
		end
	end
end

--- Returns a timeline by ID.
--- @param id string
--- @return table?
function TimelineRegistry:get(id)
	return self._timelines[id]
end

--- Returns all registered timelines as a shared frozen array.
--- Stable Id ordering makes equal-distance query ties independent of hash iteration.
--- @return { table }
function TimelineRegistry:getAll()
	if not self._sorted then
		local result = {}
		for _, timeline in pairs(self._timelines) do
			table.insert(result, timeline)
		end
		table.sort(result, function(a, b)
			return a.Id < b.Id
		end)
		self._sorted = table.freeze(result)
	end
	return self._sorted
end

--- Returns registered timelines whose retained history may intersect an AABB, Id-sorted.
--- Falls back to every timeline when there is no index or the region is too large to index.
--- @param min Vector3?
--- @param max Vector3?
--- @return { table }
function TimelineRegistry:candidates(min, max)
	if not (self._index and min and max) then
		return self:getAll()
	end
	local found = self._index:query(min, max)
	if not found then
		return self:getAll()
	end
	local result = {}
	for timeline in pairs(found) do
		table.insert(result, timeline)
	end
	table.sort(result, function(a, b)
		return a.Id < b.Id
	end)
	return result
end

--- Returns the generation of the most recently added timeline.
--- @return number
function TimelineRegistry:generation()
	return self._generation
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
	for id in pairs(self._timelines) do
		self:remove(id)
	end
end

return TimelineRegistry
