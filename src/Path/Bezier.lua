-- Chronocast v2 - Bezier Path
--
-- A cubic Bezier curve through 4 control points.

local Bezier = {}
Bezier.__index = Bezier

--- Creates a new Bezier path.
--- @param params { P0: Vector3, P1: Vector3, P2: Vector3, P3: Vector3 }
--- @return table
function Bezier.new(params)
	assert(params, "Bezier path requires parameters")
	assert(params.P0, "Bezier path requires P0")
	assert(params.P1, "Bezier path requires P1")
	assert(params.P2, "Bezier path requires P2")
	assert(params.P3, "Bezier path requires P3")

	local self = setmetatable({
		P0 = params.P0,
		P1 = params.P1,
		P2 = params.P2,
		P3 = params.P3,
		Intervals = params.Intervals or params.Samples or 20, -- Samples is the deprecated name
	}, Bezier)
	return self
end

--- Evaluates the cubic Bezier curve at alpha (0..1).
--- @param alpha number
--- @return Vector3
function Bezier:evaluate(alpha)
	local t = alpha
	local u = 1 - t
	local tt = t * t
	local uu = u * u
	local uuu = uu * u
	local ttt = tt * t

	return self.P0 * uuu + self.P1 * 3 * uu * t + self.P2 * 3 * u * tt + self.P3 * ttt
end

--- Samples the path at a given alpha (0..1).
--- Returns a CFrame oriented along the curve direction.
--- @param alpha number (0 = P0, 1 = P3)
--- @return CFrame
function Bezier:Sample(alpha)
	alpha = math.clamp(alpha, 0, 1)
	local position = self:evaluate(alpha)

	-- Calculate tangent (derivative) for orientation
	local t = alpha
	local u = 1 - t
	local tangent = self.P1 * 3 * u * u
		- self.P0 * 3 * u * u
		+ self.P2 * 6 * u * t
		- self.P1 * 6 * u * t
		+ self.P3 * 3 * t * t
		- self.P2 * 3 * t * t

	if tangent.Magnitude < 0.0001 then
		tangent = self.P3 - self.P0
	end

	local lookDirection = tangent.Unit
	local up = Vector3.new(0, 1, 0)
	if math.abs(lookDirection:Dot(up)) > 0.99 then
		up = Vector3.new(1, 0, 0)
	end
	return CFrame.lookAt(position, position + lookDirection, up)
end

--- Approximates the length of the curve by subdivision.
--- @param segments number? Number of segments for approximation
--- @return number
function Bezier:Length(segments)
	segments = segments or 20
	local length = 0
	local prev = self.P0

	for i = 1, segments do
		local alpha = i / segments
		local curr = self:evaluate(alpha)
		length += (curr - prev).Magnitude
		prev = curr
	end

	return length
end

return Bezier
