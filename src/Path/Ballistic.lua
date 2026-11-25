-- Chronocast v2 - Ballistic Path
--
-- Simulates a projectile trajectory under constant gravity.
-- Useful for lag-compensated projectile prediction.

local Ballistic = {}
Ballistic.__index = Ballistic

--- Creates a new Ballistic path.
--- @param params { Origin: Vector3, Velocity: Vector3, Gravity: number? }
--- @return table
function Ballistic.new(params)
	assert(params, "Ballistic path requires parameters")
	assert(params.Origin, "Ballistic path requires Origin")
	assert(params.Velocity, "Ballistic path requires Velocity")

	local self = setmetatable({
		Origin = params.Origin,
		Velocity = params.Velocity,
		Gravity = params.Gravity or 196.2, -- Default Roblox gravity
		TotalTime = params.TotalTime or 2.0, -- Total simulation time
		Intervals = params.Intervals or params.Samples or 30, -- Samples is the deprecated name
	}, Ballistic)
	return self
end

--- Evaluates the ballistic trajectory at alpha (0..1).
--- @param alpha number
--- @return Vector3
function Ballistic:evaluate(alpha)
	local t = alpha * self.TotalTime
	return self.Origin + self.Velocity * t + Vector3.new(0, -0.5 * self.Gravity * t * t, 0)
end

--- Samples the path at a given alpha (0..1).
--- Returns a CFrame oriented along the velocity direction.
--- @param alpha number (0 = Origin, 1 = end of TotalTime)
--- @return CFrame
function Ballistic:Sample(alpha)
	alpha = math.clamp(alpha, 0, 1)
	local position = self:evaluate(alpha)

	-- Calculate velocity at this point (derivative of position)
	local t = alpha * self.TotalTime
	local velocity = self.Velocity + Vector3.new(0, -self.Gravity * t, 0)

	if velocity.Magnitude < 0.0001 then
		return CFrame.new(position)
	end

	local lookDirection = velocity.Unit
	local up = Vector3.new(0, 1, 0)
	if math.abs(lookDirection:Dot(up)) > 0.99 then
		up = Vector3.new(1, 0, 0)
	end
	return CFrame.lookAt(position, position + lookDirection, up)
end

--- Approximates the length of the ballistic arc.
--- @param segments number?
--- @return number
function Ballistic:Length(segments)
	segments = segments or 30
	local length = 0
	local prev = self.Origin

	for i = 1, segments do
		local alpha = i / segments
		local curr = self:evaluate(alpha)
		length += (curr - prev).Magnitude
		prev = curr
	end

	return length
end

--- Returns the maximum height of the trajectory.
--- @return number
function Ballistic:MaxHeight()
	local verticalVel = self.Velocity.Y
	local maxHeight = (verticalVel * verticalVel) / (2 * self.Gravity)
	return self.Origin.Y + maxHeight
end

--- Returns the estimated landing position (assuming flat ground).
--- @return Vector3?
function Ballistic:LandingPosition()
	local verticalVel = self.Velocity.Y
	local totalTime = (verticalVel + math.sqrt(verticalVel * verticalVel + 2 * self.Gravity * self.Origin.Y))
		/ self.Gravity
	if totalTime <= 0 then
		return nil
	end
	return self:evaluate(totalTime / self.TotalTime)
end

return Ballistic
