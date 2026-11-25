-- Chronocast v2 - Spatial Index
--
-- Internal uniform grid over *retained history*, not current positions.
-- Each snapshot covers the segment from the previous snapshot's root position to
-- its own, inflated by its collision's rotation-invariant bounding radius. Linear
-- position interpolation keeps every reconstructable pose inside that region, so
-- filtering is conservative for any context time. Developers never interact with it.

local Collision = require(script.Parent.Collision)

local SpatialIndex = {}
SpatialIndex.__index = SpatialIndex

-- A sample (or query) spanning more cells than this is not gridded: oversized samples
-- are always candidates, and oversized queries scan every timeline.
local MAX_SAMPLE_CELLS = 64
local MAX_QUERY_CELLS = 4096
-- Cell coordinates are packed into one exact double: 17 bits per axis.
local CELL_LIMIT = 65535
local CELL_SPAN = 131072

local function packKey(cx, cy, cz)
	return ((cx + CELL_LIMIT) * CELL_SPAN + (cy + CELL_LIMIT)) * CELL_SPAN + (cz + CELL_LIMIT)
end

--- Creates a new spatial index with the given cell size.
--- @param cellSize number
--- @return table
function SpatialIndex.new(cellSize)
	cellSize = cellSize or 64
	assert(
		type(cellSize) == "number" and cellSize > 0 and cellSize < math.huge,
		"SpatialIndex CellSize must be finite and positive"
	)
	local self = setmetatable({
		_cellSize = cellSize,
		_cells = {}, -- packed key -> { [timeline] = sample count }
		_samples = {}, -- timeline -> { [time] = sample }; sample = { From, X0, Y0, Z0, X1, Y1, Z1 } or { From, Oversized }
		_newestTime = {}, -- timeline -> newest indexed time
		_newestPosition = {}, -- timeline -> root position at that time
		_oversized = {}, -- timeline -> oversized sample count
		_radii = setmetatable({}, { __mode = "k" }), -- definition -> bounding radius (definitions are immutable)
	}, SpatialIndex)
	return self
end

function SpatialIndex:_cell(value)
	return math.clamp(math.floor(value / self._cellSize), -CELL_LIMIT, CELL_LIMIT)
end

function SpatialIndex:_cellRange(min, max)
	local x0, y0, z0 = self:_cell(min.X), self:_cell(min.Y), self:_cell(min.Z)
	local x1, y1, z1 = self:_cell(max.X), self:_cell(max.Y), self:_cell(max.Z)
	return x0, y0, z0, x1, y1, z1, (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1)
end

function SpatialIndex:_radius(definition)
	local radius = self._radii[definition]
	if not radius then
		radius = Collision.boundingRadius(definition)
		self._radii[definition] = radius
	end
	return radius
end

--- Indexes a snapshot. A snapshot at an already-indexed time replaces that sample.
--- @param timeline table
--- @param snapshot table
function SpatialIndex:addSample(timeline, snapshot)
	local time = snapshot.Time
	local position = snapshot.Transform.Position
	local samples = self._samples[timeline]
	local newestTime = self._newestTime[timeline]
	local from
	if samples and samples[time] then
		from = samples[time].From
		self:removeSample(timeline, time)
		samples = self._samples[timeline]
	elseif newestTime and newestTime < time then
		from = self._newestPosition[timeline]
	else
		from = position
	end
	if not samples then
		samples = {}
		self._samples[timeline] = samples
	end
	if not newestTime or newestTime <= time then
		self._newestTime[timeline] = time
		self._newestPosition[timeline] = position
	end

	local definition = snapshot.Collision
	if not definition then
		samples[time] = { From = from }
		return
	end
	local radius = self:_radius(definition)
	local x0 = self:_cell(math.min(from.X, position.X) - radius)
	local y0 = self:_cell(math.min(from.Y, position.Y) - radius)
	local z0 = self:_cell(math.min(from.Z, position.Z) - radius)
	local x1 = self:_cell(math.max(from.X, position.X) + radius)
	local y1 = self:_cell(math.max(from.Y, position.Y) + radius)
	local z1 = self:_cell(math.max(from.Z, position.Z) + radius)
	if (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1) > MAX_SAMPLE_CELLS then
		samples[time] = { From = from, Oversized = true }
		self._oversized[timeline] = (self._oversized[timeline] or 0) + 1
		return
	end
	samples[time] = { From = from, X0 = x0, Y0 = y0, Z0 = z0, X1 = x1, Y1 = y1, Z1 = z1 }
	local cells = self._cells
	for cx = x0, x1 do
		for cy = y0, y1 do
			for cz = z0, z1 do
				local key = packKey(cx, cy, cz)
				local cell = cells[key]
				if not cell then
					cell = {}
					cells[key] = cell
				end
				cell[timeline] = (cell[timeline] or 0) + 1
			end
		end
	end
end

--- Removes one indexed snapshot (evicted or replaced history).
--- @param timeline table
--- @param time number
function SpatialIndex:removeSample(timeline, time)
	local samples = self._samples[timeline]
	local sample = samples and samples[time]
	if not sample then
		return
	end
	samples[time] = nil
	if sample.Oversized then
		local remaining = self._oversized[timeline] - 1
		self._oversized[timeline] = remaining > 0 and remaining or nil
	elseif sample.X0 then
		local cells = self._cells
		for cx = sample.X0, sample.X1 do
			for cy = sample.Y0, sample.Y1 do
				for cz = sample.Z0, sample.Z1 do
					local key = packKey(cx, cy, cz)
					local cell = cells[key]
					local remaining = cell[timeline] - 1
					if remaining > 0 then
						cell[timeline] = remaining
					else
						cell[timeline] = nil
						if next(cell) == nil then
							cells[key] = nil
						end
					end
				end
			end
		end
	end
	if next(samples) == nil then
		self._samples[timeline] = nil
		self._newestTime[timeline] = nil
		self._newestPosition[timeline] = nil
	end
end

--- Removes every sample belonging to a timeline.
--- @param timeline table
function SpatialIndex:removeTimeline(timeline)
	local samples = self._samples[timeline]
	if samples then
		local times = {}
		for time in pairs(samples) do
			table.insert(times, time)
		end
		for _, time in ipairs(times) do
			self:removeSample(timeline, time)
		end
	end
	self._samples[timeline] = nil
	self._newestTime[timeline] = nil
	self._newestPosition[timeline] = nil
	self._oversized[timeline] = nil
end

--- Returns the set of timelines whose retained history may intersect the AABB,
--- or nil when the region is too large to enumerate (callers then scan everything).
--- @param min Vector3
--- @param max Vector3
--- @return { [table]: true }?
function SpatialIndex:query(min, max)
	local x0, y0, z0, x1, y1, z1, count = self:_cellRange(min, max)
	if count > MAX_QUERY_CELLS then
		return nil
	end
	local found = {}
	for timeline in pairs(self._oversized) do
		found[timeline] = true
	end
	for cx = x0, x1 do
		for cy = y0, y1 do
			for cz = z0, z1 do
				local cell = self._cells[packKey(cx, cy, cz)]
				if cell then
					for timeline in pairs(cell) do
						found[timeline] = true
					end
				end
			end
		end
	end
	return found
end

--- Returns the number of occupied cells (diagnostics and tests).
--- @return number
function SpatialIndex:cellCount()
	local count = 0
	for _ in pairs(self._cells) do
		count += 1
	end
	return count
end

--- Clears the spatial index.
function SpatialIndex:clear()
	self._cells = {}
	self._samples = {}
	self._newestTime = {}
	self._newestPosition = {}
	self._oversized = {}
end

return SpatialIndex
