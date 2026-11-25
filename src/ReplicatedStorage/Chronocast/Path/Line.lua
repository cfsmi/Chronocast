-- Chronocast v2 - Line Path
--
-- A straight line between two points.

local Line = {}
Line.__index = Line

--- Creates a new Line path.
--- @param params { Start: Vector3, End: Vector3 }
--- @return table
function Line.new(params)
	assert(params, "Line path requires parameters")
	assert(params.Start, "Line path requires Start")
	assert(params.End, "Line path requires End")

	local delta = params.End - params.Start
	local self = setmetatable({
		Start = params.Start,
		End = params.End,
		Direction = delta.Magnitude > 0 and delta.Unit or Vector3.zAxis,
		_length = delta.Magnitude,
		Samples = params.Samples or 10,
	}, Line)
	return self
end

--- Samples the path at a given alpha (0..1).
--- @param alpha number (0 = Start, 1 = End)
--- @return CFrame
function Line:Sample(alpha)
	alpha = math.clamp(alpha, 0, 1)
	local position = self.Start:Lerp(self.End, alpha)

	-- Orient CFrame along the line direction
	local lookDirection = self.Direction
	local up = Vector3.new(0, 1, 0)
	if math.abs(lookDirection:Dot(up)) > 0.99 then
		up = Vector3.new(1, 0, 0)
	end
	return CFrame.lookAt(position, position + lookDirection, up)
end

--- Returns the length of the path.
--- @return number
function Line:Length()
	return self._length
end

return Line