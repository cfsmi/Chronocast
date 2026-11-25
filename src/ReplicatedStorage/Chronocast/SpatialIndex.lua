-- Chronocast v2 - Spatial Index
--
-- Internal spatial index for filtering candidate timelines before reconstruction.
-- Uses a uniform grid for simplicity and performance.
-- Developers never interact with this directly.

local SpatialIndex = {}
SpatialIndex.__index = SpatialIndex

--- Creates a new spatial index with the given cell size.
--- @param cellSize number
--- @return table
function SpatialIndex.new(cellSize)
	local self = setmetatable({
		_cellSize = cellSize or 64,
		_grid = {}, -- "cx,cy,cz" -> { timeline, ... }
		_timelineCells = {}, -- timelineId -> { "cx,cy,cz", ... }
	}, SpatialIndex)
	return self
end

--- Converts a position to grid cell coordinates.
--- @param position Vector3
--- @return number, number, number (cx, cy, cz)
function SpatialIndex:_positionToCell(position)
	local cx = math.floor(position.X / self._cellSize)
	local cy = math.floor(position.Y / self._cellSize)
	local cz = math.floor(position.Z / self._cellSize)
	return cx, cy, cz
end

--- Returns the cell key for given coordinates.
--- @param cx number
--- @param cy number
--- @param cz number
--- @return string
function SpatialIndex:_cellKey(cx, cy, cz)
	return cx .. "," .. cy .. "," .. cz
end

--- Adds a timeline to the spatial index.
--- @param timeline table
function SpatialIndex:add(timeline)
	if not timeline then
		return
	end

	-- Get the timeline's current position from its latest snapshot
	local state = timeline:getState(timeline:getSnapshots()[1] and timeline:getSnapshots()[1].Time or 0)
	if not state then
		return
	end

	local position = state.Transform.Position
	local cx, cy, cz = self:_positionToCell(position)
	local key = self:_cellKey(cx, cy, cz)

	-- Add to grid
	if not self._grid[key] then
		self._grid[key] = {}
	end
	table.insert(self._grid[key], timeline)

	-- Track which cells this timeline is in
	if not self._timelineCells[timeline.Id] then
		self._timelineCells[timeline.Id] = {}
	end
	table.insert(self._timelineCells[timeline.Id], key)
end

--- Removes a timeline from the spatial index.
--- @param id string
function SpatialIndex:remove(id)
	local cells = self._timelineCells[id]
	if not cells then
		return
	end

	for _, key in ipairs(cells) do
		if self._grid[key] then
			for i = #self._grid[key], 1, -1 do
				if self._grid[key][i].Id == id then
					table.remove(self._grid[key], i)
					break
				end
			end
			if #self._grid[key] == 0 then
				self._grid[key] = nil
			end
		end
	end

	self._timelineCells[id] = nil
end

--- Updates a timeline's position in the index.
--- @param timeline table
function SpatialIndex:update(timeline)
	self:remove(timeline.Id)
	self:add(timeline)
end

--- Queries the spatial index for timelines in a region.
--- @param region table { Min: Vector3, Max: Vector3 }
--- @return { table }
function SpatialIndex:query(region)
	local minCellX, minCellY, minCellZ = self:_positionToCell(region.Min)
	local maxCellX, maxCellY, maxCellZ = self:_positionToCell(region.Max)

	local seen = {}
	local results = {}

	for cx = minCellX, maxCellX do
		for cy = minCellY, maxCellY do
			for cz = minCellZ, maxCellZ do
				local key = self:_cellKey(cx, cy, cz)
				local cell = self._grid[key]
				if cell then
					for _, timeline in ipairs(cell) do
						if not seen[timeline.Id] then
							seen[timeline.Id] = true
							table.insert(results, timeline)
						end
					end
				end
			end
		end
	end

	return results
end

--- Queries for timelines within a radius of a point.
--- @param center Vector3
--- @param radius number
--- @return { table }
function SpatialIndex:queryRadius(center, radius)
	local region = {
		Min = center - Vector3.new(radius, radius, radius),
		Max = center + Vector3.new(radius, radius, radius),
	}

	local candidates = self:query(region)
	local results = {}
	local radiusSq = radius * radius

	for _, timeline in ipairs(candidates) do
		local state = timeline:getState(timeline:getSnapshots()[1] and timeline:getSnapshots()[1].Time or 0)
		if state then
			local distSq = (state.Transform.Position - center).MagnitudeSq
			if distSq <= radiusSq then
				table.insert(results, timeline)
			end
		end
	end

	return results
end

--- Clears the spatial index.
function SpatialIndex:clear()
	self._grid = {}
	self._timelineCells = {}
end

return SpatialIndex