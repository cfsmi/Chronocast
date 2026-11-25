-- Chronocast v2 - Ring Buffer
--
-- A fixed-capacity ring buffer for storing snapshot history.
-- When full, oldest entries are overwritten.
-- Constant memory usage, O(1) insertions.

local Immutable = require(script.Parent.Parent.Immutable)

local RingBuffer = {}
RingBuffer.__index = RingBuffer

--- Creates a new RingBuffer with the given capacity.
--- @param capacity number
--- @return table
function RingBuffer.new(capacity)
	assert(type(capacity) == "number" and capacity == capacity and capacity < math.huge
		and capacity > 0 and capacity % 1 == 0, "RingBuffer capacity must be a finite positive integer")
	local self = setmetatable({
		_buffer = {},
		_timeSlots = {},
		_capacity = capacity,
		_head = 0, -- Newest entry position
		_count = 0, -- Number of valid entries
	}, RingBuffer)
	return self
end

--- Returns the capacity of the buffer.
--- @return number
function RingBuffer:capacity()
	return self._capacity
end

--- Returns the number of entries in the buffer.
--- @return number
function RingBuffer:count()
	return self._count
end

--- Returns whether the buffer is empty.
--- @return boolean
function RingBuffer:isEmpty()
	return self._count == 0
end

--- Returns whether the buffer is full.
--- @return boolean
function RingBuffer:isFull()
	return self._count == self._capacity
end

--- Pushes a new entry to the buffer.
--- Overwrites oldest entry if buffer is full.
--- @param entry table
function RingBuffer:push(entry)
	assert(type(entry) == "table", "RingBuffer entries must be tables")
	local time = entry.Time
	assert(type(time) == "number" and time == time and math.abs(time) < math.huge,
		"Snapshot Time must be a finite number")
	local existingSlot = self._timeSlots[time]
	local newest = self:newest()
	assert(existingSlot ~= nil or newest == nil or time > newest.Time,
		"New snapshots must have increasing timestamps")
	local snapshot = Immutable.copyAndFreeze(entry)

	if existingSlot then
		-- Replace in place so timestamps remain in their original chronological slot.
		self._buffer[existingSlot] = snapshot
		return
	end

	local nextSlot = (self._head % self._capacity) + 1
	if self._count == self._capacity then
		local oldestSlot = (self._head - self._count) % self._capacity + 1
		local evicted = self._buffer[oldestSlot]
		if evicted then
			self._timeSlots[evicted.Time] = nil
		end
	else
		self._count += 1
	end

	self._head = nextSlot
	self._buffer[self._head] = snapshot
	self._timeSlots[time] = self._head
end

--- Returns the entry at the given index (1-based, oldest first).
--- @param index number
--- @return table?
function RingBuffer:get(index)
	if index < 1 or index > self._count then
		return nil
	end
	local offset = (self._head - self._count + index - 1) % self._capacity + 1
	return self._buffer[offset]
end

--- Returns the newest entry.
--- @return table?
function RingBuffer:newest()
	if self._count == 0 then
		return nil
	end
	return self._buffer[self._head]
end

--- Returns the oldest entry.
--- @return table?
function RingBuffer:oldest()
	if self._count == 0 then
		return nil
	end
	local offset = (self._head - self._count) % self._capacity + 1
	return self._buffer[offset]
end

--- Returns the entry at the given position from the newest (0 = newest, 1 = one before, etc.)
--- @param offset number
--- @return table?
function RingBuffer:fromNewest(offset)
	if offset < 0 or offset >= self._count then
		return nil
	end
	local idx = (self._head - offset - 1) % self._capacity + 1
	return self._buffer[idx]
end

--- Iterates over all entries from oldest to newest.
--- @return function iterator
function RingBuffer:entries()
	local i = 0
	local buffer = self._buffer
	local count = self._count
	local head = self._head
	local capacity = self._capacity
	return function()
		i += 1
		if i > count then
			return nil
		end
		local offset = (head - count + i - 1) % capacity + 1
		return buffer[offset]
	end
end

--- Clears all entries from the buffer.
function RingBuffer:clear()
	self._buffer = {}
	self._timeSlots = {}
	self._head = 0
	self._count = 0
end

--- Finds two snapshots bracketing a given time.
--- Returns the snapshot before and after the target time.
--- @param time number
--- @return table?, table? (before, after)
function RingBuffer:findBracketingSnapshots(time)
	if self._count == 0 then
		return nil, nil
	end

	local before = nil
	local after = nil

	for i = 1, self._count do
		local entry = self:get(i)
		if entry.Time <= time then
			before = entry
		end
		if entry.Time >= time and after == nil then
			after = entry
		end
	end

	return before, after
end

--- Finds the nearest snapshot to a given time.
--- @param time number
--- @return table?
function RingBuffer:nearestSnapshot(time)
	if self._count == 0 then
		return nil
	end

	local nearest = nil
	local nearestDist = math.huge

	for i = 1, self._count do
		local entry = self:get(i)
		local dist = math.abs(entry.Time - time)
		if dist < nearestDist then
			nearest = entry
			nearestDist = dist
		end
	end

	return nearest
end

return RingBuffer