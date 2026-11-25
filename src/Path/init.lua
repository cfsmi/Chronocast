-- Chronocast v2 - Path Module
--
-- Paths define motion separate from collision volume.
-- All paths implement a Sample(alpha) function where alpha is 0..1.

local Path = {}
Path.__index = Path

local LineModule = require(script.Line)
local BezierModule = require(script.Bezier)
local BallisticModule = require(script.Ballistic)
local CustomModule = require(script.Custom)

--- Creates a new Line path.
--- @param params { Start: Vector3, End: Vector3 }
--- @return table
function Path.Line(params)
	return LineModule.new(params)
end

--- Creates a new Bezier path.
--- @param params { P0: Vector3, P1: Vector3, P2: Vector3, P3: Vector3 }
--- @return table
function Path.Bezier(params)
	return BezierModule.new(params)
end

--- Creates a new Ballistic path.
--- @param params { Origin: Vector3, Velocity: Vector3, Gravity: number?, TotalTime: number? }
--- @return table
function Path.Ballistic(params)
	return BallisticModule.new(params)
end

--- Creates a new Custom path.
--- @param params { Sample: fun(self: table, alpha: number): CFrame, Length: fun(self: table): number?, Intervals: number? }
--- @return table
function Path.Custom(params)
	return CustomModule.new(params)
end

return Path
