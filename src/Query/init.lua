-- Pure temporal collision queries. All collision geometry is evaluated in world space.
local QueryEngine = {}
local Collision = require(script.Parent.Collision)
local EPSILON = 1e-7

local function miss()
	return { Hit = false }
end
local function unitOr(v, fallback)
	return v.Magnitude > EPSILON and v.Unit or fallback
end
local function result(timeline, distance, position, normal)
	return {
		Hit = true,
		Timeline = timeline,
		Distance = distance,
		Position = position,
		Normal = unitOr(normal, Vector3.yAxis),
	}
end
local function rayInput(p)
	local length = p.Direction.Magnitude
	assert(length > EPSILON, "Ray Direction must be nonzero")
	return p.Origin, p.Direction / length, p.MaxDistance or math.huge
end

local function rayBox(p, box, timeline)
	local origin, direction, maxDistance = rayInput(p)
	local cf = box.Offset
	local o, d, half = cf:PointToObjectSpace(origin), cf:VectorToObjectSpace(direction), box.Size / 2
	local tMin, tMax, nearNormal = -math.huge, math.huge, Vector3.zero
	for axis = 1, 3 do
		local ov = axis == 1 and o.X or (axis == 2 and o.Y or o.Z)
		local dv = axis == 1 and d.X or (axis == 2 and d.Y or d.Z)
		local h = axis == 1 and half.X or (axis == 2 and half.Y or half.Z)
		if math.abs(dv) <= EPSILON then
			if ov < -h or ov > h then
				return miss()
			end
		else
			local t1, t2 = (-h - ov) / dv, (h - ov) / dv
			local sign = -1
			if t1 > t2 then
				t1, t2, sign = t2, t1, 1
			end
			if t1 > tMin then
				tMin = t1
				nearNormal = axis == 1 and Vector3.new(sign, 0, 0)
					or (axis == 2 and Vector3.new(0, sign, 0) or Vector3.new(0, 0, sign))
			end
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return miss()
			end
		end
	end
	-- If the exit slab lies behind the origin, the whole box is behind the ray.
	if tMax < 0 then
		return miss()
	end
	local inside = tMin < 0
	local t = inside and 0 or tMin
	if t < 0 or t > maxDistance then
		return miss()
	end
	local localNormal = inside and -d or nearNormal
	return result(timeline, t, origin + direction * t, cf:VectorToWorldSpace(unitOr(localNormal, Vector3.yAxis)))
end

local function raySphereGeometry(origin, direction, maxDistance, center, radius, timeline)
	local m = origin - center
	local b, c = m:Dot(direction), m:Dot(m) - radius * radius
	local discriminant = b * b - c
	if discriminant < 0 then
		return miss()
	end
	local inside = c <= 0
	local t = inside and 0 or (-b - math.sqrt(discriminant))
	if t < 0 or t > maxDistance then
		return miss()
	end
	local point = origin + direction * t
	return result(timeline, t, point, inside and -direction or (point - center))
end
local function raySphere(p, sphere, timeline)
	local o, d, maxDistance = rayInput(p)
	return raySphereGeometry(o, d, maxDistance, sphere.Offset.Position, sphere.Radius, timeline)
end

local function closestPointSegment(point, a, b)
	local ab = b - a
	local t = ab:Dot(ab) > EPSILON and math.clamp((point - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
	return a + ab * t, t
end
local function capsuleEnds(capsule)
	local delta = capsule.Offset.UpVector * (capsule.Height / 2)
	return capsule.Offset.Position - delta, capsule.Offset.Position + delta
end
local function rayCapsule(p, capsule, timeline)
	local origin, direction, maxDistance = rayInput(p)
	local cf, radius, half = capsule.Offset, capsule.Radius, capsule.Height / 2
	local o, d = cf:PointToObjectSpace(origin), cf:VectorToObjectSpace(direction)
	local candidates = {}
	local a = d.X * d.X + d.Z * d.Z
	local b = 2 * (o.X * d.X + o.Z * d.Z)
	local c = o.X * o.X + o.Z * o.Z - radius * radius
	local disc = b * b - 4 * a * c
	if a > EPSILON and disc >= 0 then
		for _, t in ipairs({ (-b - math.sqrt(disc)) / (2 * a), (-b + math.sqrt(disc)) / (2 * a) }) do
			local y = o.Y + d.Y * t
			if t >= 0 and t <= maxDistance and y >= -half - EPSILON and y <= half + EPSILON then
				local point = origin + direction * t
				local localPoint = o + d * t
				table.insert(
					candidates,
					result(timeline, t, point, cf:VectorToWorldSpace(Vector3.new(localPoint.X, 0, localPoint.Z)))
				)
			end
		end
	end
	for _, y in ipairs({ -half, half }) do
		local hit = raySphereGeometry(origin, direction, maxDistance, cf * Vector3.new(0, y, 0), radius, timeline)
		if hit.Hit then
			table.insert(candidates, hit)
		end
	end
	local nearest = closestPointSegment(origin, cf * Vector3.new(0, -half, 0), cf * Vector3.new(0, half, 0))
	if (origin - nearest).Magnitude <= radius and maxDistance >= 0 then
		table.insert(candidates, result(timeline, 0, origin, origin - nearest))
	end
	local best
	for _, hit in ipairs(candidates) do
		if not best or hit.Distance < best.Distance then
			best = hit
		end
	end
	return best or miss()
end

local function sphereSphere(p, target, timeline)
	local delta = target.Offset.Position - p.Origin
	local distance = delta.Magnitude
	local penetration = (p.Radius or 0) + target.Radius - distance
	if penetration < 0 then
		return miss()
	end
	local normal = unitOr(delta, Vector3.yAxis)
	return result(timeline, distance, target.Offset.Position - normal * target.Radius, -normal)
end
local function sphereBox(p, box, timeline)
	local localCenter = box.Offset:PointToObjectSpace(p.Origin)
	local half = box.Size / 2
	local closest = Vector3.new(
		math.clamp(localCenter.X, -half.X, half.X),
		math.clamp(localCenter.Y, -half.Y, half.Y),
		math.clamp(localCenter.Z, -half.Z, half.Z)
	)
	local delta = localCenter - closest
	local distance = delta.Magnitude
	if distance > (p.Radius or 0) then
		return miss()
	end
	local normalLocal = delta.Unit
	if distance <= EPSILON then
		local dx, dy, dz =
			half.X - math.abs(localCenter.X), half.Y - math.abs(localCenter.Y), half.Z - math.abs(localCenter.Z)
		if dx <= dy and dx <= dz then
			normalLocal = Vector3.new(localCenter.X < 0 and -1 or 1, 0, 0)
			closest = Vector3.new(normalLocal.X * half.X, localCenter.Y, localCenter.Z)
		elseif dy <= dz then
			normalLocal = Vector3.new(0, localCenter.Y < 0 and -1 or 1, 0)
			closest = Vector3.new(localCenter.X, normalLocal.Y * half.Y, localCenter.Z)
		else
			normalLocal = Vector3.new(0, 0, localCenter.Z < 0 and -1 or 1)
			closest = Vector3.new(localCenter.X, localCenter.Y, normalLocal.Z * half.Z)
		end
	end
	local normal = box.Offset:VectorToWorldSpace(normalLocal)
	return result(timeline, distance, box.Offset * closest, normal)
end

local function boxAxes(cf)
	return { cf.RightVector, cf.UpVector, -cf.LookVector }
end
local function boxBox(p, box, timeline)
	local cfA, cfB = p.CFrame or CFrame.new(p.Origin), box.Offset
	local a, b = p.Size / 2, box.Size / 2
	local A, B = boxAxes(cfA), boxAxes(cfB)
	local delta = cfB.Position - cfA.Position
	local axes = {}
	for i = 1, 3 do
		table.insert(axes, A[i])
		table.insert(axes, B[i])
	end
	for i = 1, 3 do
		for j = 1, 3 do
			table.insert(axes, A[i]:Cross(B[j]))
		end
	end
	local smallest, normal = math.huge, Vector3.yAxis
	for _, rawAxis in ipairs(axes) do
		if rawAxis.Magnitude > EPSILON then
			local axis = rawAxis.Unit
			local ra = a.X * math.abs(A[1]:Dot(axis)) + a.Y * math.abs(A[2]:Dot(axis)) + a.Z * math.abs(A[3]:Dot(axis))
			local rb = b.X * math.abs(B[1]:Dot(axis)) + b.Y * math.abs(B[2]:Dot(axis)) + b.Z * math.abs(B[3]:Dot(axis))
			local overlap = ra + rb - math.abs(delta:Dot(axis))
			if overlap < -EPSILON then
				return miss()
			end
			if overlap < smallest then
				smallest = overlap
				normal = delta:Dot(axis) < 0 and -axis or axis
			end
		end
	end
	local towardQuery = cfB:VectorToObjectSpace(-normal)
	local contact = cfB
		* Vector3.new(math.sign(towardQuery.X) * b.X, math.sign(towardQuery.Y) * b.Y, math.sign(towardQuery.Z) * b.Z)
	return result(timeline, math.max(0, smallest), contact, -normal)
end

local function segmentSegment(a0, a1, b0, b1)
	local u, v, w = a1 - a0, b1 - b0, a0 - b0
	local aa, bb, cc, dd, ee = u:Dot(u), u:Dot(v), v:Dot(v), u:Dot(w), v:Dot(w)
	local s, t
	if aa <= EPSILON and cc <= EPSILON then
		s, t = 0, 0
	elseif aa <= EPSILON then
		s, t = 0, math.clamp(ee / cc, 0, 1)
	elseif cc <= EPSILON then
		t, s = 0, math.clamp(-dd / aa, 0, 1)
	else
		local denom = aa * cc - bb * bb
		s = denom > EPSILON and math.clamp((bb * ee - cc * dd) / denom, 0, 1) or 0
		t = (bb * s + ee) / cc
		if t < 0 then
			t, s = 0, math.clamp(-dd / aa, 0, 1)
		elseif t > 1 then
			t, s = 1, math.clamp((bb - dd) / aa, 0, 1)
		end
	end
	return a0 + u * s, b0 + v * t
end
local function capsuleSphere(p, target, timeline)
	local a, b = capsuleEnds(p)
	local point, _ = closestPointSegment(target.Offset.Position, a, b)
	local delta = target.Offset.Position - point
	local distance = delta.Magnitude
	if distance > p.Radius + target.Radius then
		return miss()
	end
	local n = unitOr(delta, Vector3.yAxis)
	return result(timeline, distance, target.Offset.Position - n * target.Radius, -n)
end
local function sphereCapsule(p, target, timeline)
	local a, b = capsuleEnds(target)
	local axisPoint = closestPointSegment(p.Origin, a, b)
	local delta = axisPoint - p.Origin
	local distance = delta.Magnitude
	if distance > (p.Radius or 0) + target.Radius then
		return miss()
	end
	local n = unitOr(delta, Vector3.yAxis)
	return result(timeline, distance, axisPoint - n * target.Radius, -n)
end
local function capsuleCapsule(p, target, timeline)
	local a0, a1 = capsuleEnds(p)
	local b0, b1 = capsuleEnds(target)
	local pa, pb = segmentSegment(a0, a1, b0, b1)
	local delta, distance = pb - pa, (pb - pa).Magnitude
	if distance > p.Radius + target.Radius then
		return miss()
	end
	local n = unitOr(delta, Vector3.yAxis)
	return result(timeline, distance, pb - n * target.Radius, -n)
end
local function capsuleBox(p, box, timeline)
	local a, b = capsuleEnds(p)
	local localA, localB = box.Offset:PointToObjectSpace(a), box.Offset:PointToObjectSpace(b)
	local half = box.Size / 2
	local function nearest(t)
		local point = localA:Lerp(localB, t)
		local closest = Vector3.new(
			math.clamp(point.X, -half.X, half.X),
			math.clamp(point.Y, -half.Y, half.Y),
			math.clamp(point.Z, -half.Z, half.Z)
		)
		return (point - closest).Magnitude, point, closest
	end
	-- Exact piecewise-quadratic minimum of segment-to-AABB distance. Each
	-- interval between slab crossings has a fixed set of clamped coordinates.
	local breaks = { 0, 1 }
	local direction = localB - localA
	for axis = 1, 3 do
		local start = axis == 1 and localA.X or (axis == 2 and localA.Y or localA.Z)
		local delta = axis == 1 and direction.X or (axis == 2 and direction.Y or direction.Z)
		local extent = axis == 1 and half.X or (axis == 2 and half.Y or half.Z)
		if math.abs(delta) > EPSILON then
			for _, boundary in ipairs({ -extent, extent }) do
				local t = (boundary - start) / delta
				if t > 0 and t < 1 then
					table.insert(breaks, t)
				end
			end
		end
	end
	table.sort(breaks)
	local bestDistance, bestSegment, bestBox = math.huge, localA, Vector3.zero
	local function consider(t)
		local distance, segmentPoint, boxPoint = nearest(math.clamp(t, 0, 1))
		if distance < bestDistance then
			bestDistance, bestSegment, bestBox = distance, segmentPoint, boxPoint
		end
	end
	for i = 1, #breaks do
		consider(breaks[i])
	end
	for i = 1, #breaks - 1 do
		local lo, hi = breaks[i], breaks[i + 1]
		local mid = (lo + hi) / 2
		local point = localA:Lerp(localB, mid)
		local numerator, denominator = 0, 0
		for axis = 1, 3 do
			local value = axis == 1 and point.X or (axis == 2 and point.Y or point.Z)
			local delta = axis == 1 and direction.X or (axis == 2 and direction.Y or direction.Z)
			local extent = axis == 1 and half.X or (axis == 2 and half.Y or half.Z)
			local bound = value < -extent and -extent or (value > extent and extent or nil)
			if bound ~= nil then
				local start = axis == 1 and localA.X or (axis == 2 and localA.Y or localA.Z)
				numerator += delta * (start - bound)
				denominator += delta * delta
			end
		end
		if denominator > EPSILON then
			consider(math.clamp(-numerator / denominator, lo, hi))
		end
	end
	local distance, segmentPoint, boxPoint = bestDistance, bestSegment, bestBox
	if distance > p.Radius + EPSILON then
		return miss()
	end
	if distance <= EPSILON then
		return sphereBox({ Origin = box.Offset * segmentPoint, Radius = 0 }, box, timeline)
	end
	return result(
		timeline,
		distance,
		box.Offset * boxPoint,
		box.Offset:VectorToWorldSpace((segmentPoint - boxPoint).Unit)
	)
end

local targetHandlers = {
	Ray = { Box = rayBox, Sphere = raySphere, Capsule = rayCapsule },
	Sphere = { Box = sphereBox, Sphere = sphereSphere, Capsule = sphereCapsule },
	Box = {
		Box = boxBox,
		Sphere = function(p, c, t)
			local queryBox = { Offset = p.CFrame or CFrame.new(p.Origin), Size = p.Size }
			local hit = sphereBox({ Origin = c.Offset.Position, Radius = c.Radius }, queryBox, t)
			if hit.Hit then
				hit.Normal = -hit.Normal
				hit.Position = c.Offset.Position + hit.Normal * c.Radius
			end
			return hit
		end,
		Capsule = function(p, c, t)
			local hit = capsuleBox(c, { Offset = p.CFrame or CFrame.new(p.Origin), Size = p.Size }, t)
			if hit.Hit then
				local a, b = capsuleEnds(c)
				local axisPoint = closestPointSegment(hit.Position, a, b)
				hit.Normal = unitOr(hit.Position - axisPoint, -hit.Normal)
				hit.Position = axisPoint + hit.Normal * c.Radius
			end
			return hit
		end,
	},
	Capsule = {
		Box = function(p, c, t)
			return capsuleBox({ Offset = p.CFrame or CFrame.new(p.Origin), Radius = p.Radius, Height = p.Height }, c, t)
		end,
		Sphere = function(p, c, t)
			return capsuleSphere(
				{ Offset = p.CFrame or CFrame.new(p.Origin), Radius = p.Radius, Height = p.Height },
				c,
				t
			)
		end,
		Capsule = function(p, c, t)
			return capsuleCapsule(
				{ Offset = p.CFrame or CFrame.new(p.Origin), Radius = p.Radius, Height = p.Height },
				c,
				t
			)
		end,
	},
}

local function queryOne(parameters, collisionDef, timeline, shape)
	if collisionDef.Shape == "Compound" then
		-- Children are tested in definition order; strict < keeps the first of equal hits.
		local best = miss()
		for _, child in ipairs(collisionDef.Children) do
			local hit = queryOne(parameters, child, timeline, shape)
			if hit.Hit and (not best.Hit or hit.Distance < best.Distance) then
				best = hit
			end
		end
		return best
	end
	local handlers = targetHandlers[shape]
	local handler = handlers and handlers[collisionDef.Shape]
	assert(
		handler,
		string.format("Unsupported query/target collision pair: %s/%s", tostring(shape), tostring(collisionDef.Shape))
	)
	local hit = handler(parameters, collisionDef, timeline)
	if hit.Hit then
		hit.Name = collisionDef.Name
	end
	return hit
end

local function isFinite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function isFiniteVector(value)
	return typeof(value) == "Vector3" and isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z)
end
local function isNonNegative(value)
	return isFinite(value) and value >= 0
end

-- Public-seam validation for Cast and Overlap. A Path supplies each pose's Origin/CFrame.
local function validate(params, operation)
	local shape, p, path = params.Shape, params.Parameters, params.Path
	assert(targetHandlers[shape], operation .. ": unsupported Shape " .. tostring(shape))
	assert(type(p) == "table", operation .. " requires Parameters")
	assert(
		path == nil or (type(path) == "table" and type(path.Sample) == "function"),
		"Path must implement Sample(alpha)"
	)
	assert(params.Filter == nil or type(params.Filter) == "function", "Filter must be a function")
	local posed = path == nil
	if shape == "Ray" then
		assert(not posed or isFiniteVector(p.Origin), "Ray Origin must be a finite Vector3")
		assert(
			isFiniteVector(p.Direction) and p.Direction.Magnitude > EPSILON,
			"Ray Direction must be a finite nonzero Vector3"
		)
		assert(
			p.MaxDistance == nil or (type(p.MaxDistance) == "number" and p.MaxDistance >= 0),
			"Ray MaxDistance must be a non-negative number"
		)
		return
	end
	assert(p.CFrame == nil or typeof(p.CFrame) == "CFrame", shape .. " CFrame must be a CFrame")
	if shape == "Sphere" then
		assert(not posed or isFiniteVector(p.Origin), "Sphere Origin must be a finite Vector3")
		assert(isNonNegative(p.Radius), "Sphere Radius must be finite and non-negative")
	else
		assert(not posed or p.CFrame ~= nil or isFiniteVector(p.Origin), shape .. " requires an Origin or CFrame")
		if shape == "Box" then
			assert(
				isFiniteVector(p.Size) and p.Size.X >= 0 and p.Size.Y >= 0 and p.Size.Z >= 0,
				"Box Size must be a finite non-negative Vector3"
			)
		else
			assert(isNonNegative(p.Radius), "Capsule Radius must be finite and non-negative")
			assert(isNonNegative(p.Height), "Capsule Height must be finite and non-negative")
		end
	end
end

-- Conservative world AABB of one query pose, or nil when it is unbounded.
local function poseBounds(shape, p)
	if shape == "Ray" then
		local maxDistance = p.MaxDistance or math.huge
		if
			not isFinite(maxDistance)
			or typeof(p.Origin) ~= "Vector3"
			or typeof(p.Direction) ~= "Vector3"
			or p.Direction.Magnitude <= EPSILON
		then
			return nil
		end
		local a, b = p.Origin, p.Origin + p.Direction.Unit * maxDistance
		return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)),
			Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	end
	local center = shape ~= "Sphere" and p.CFrame and p.CFrame.Position or p.Origin
	if typeof(center) ~= "Vector3" then
		return nil
	end
	local reach
	if shape == "Sphere" then
		reach = p.Radius or 0
	elseif shape == "Box" then
		reach = typeof(p.Size) == "Vector3" and p.Size.Magnitude / 2 or nil
	else
		reach = (p.Height or 0) / 2 + (p.Radius or 0)
	end
	if not isFinite(reach) then
		return nil
	end
	local pad = Vector3.new(reach, reach, reach)
	return center - pad, center + pad
end

-- Discrete poses: N intervals produce N + 1 poses including both endpoints.
local function posesFor(params)
	local parameters, path = params.Parameters, params.Path
	if not path then
		return { { Parameters = parameters, Traveled = 0 } }
	end
	local samples = path.Intervals or path.Samples or 10
	assert(
		type(samples) == "number" and samples == samples and samples < math.huge and samples > 0 and samples % 1 == 0,
		"Path Intervals must be a finite positive integer"
	)
	local poses = {}
	local previousPosition, traveled = nil, 0
	for i = 0, samples do
		local cf = path:Sample(i / samples)
		assert(typeof(cf) == "CFrame", "Path:Sample(alpha) must return a CFrame")
		if previousPosition then
			traveled += (cf.Position - previousPosition).Magnitude
		end
		previousPosition = cf.Position
		local sampleParams = table.clone(parameters)
		sampleParams.Origin = cf.Position
		-- Moving query volumes follow the path frame even when no initial frame
		-- was supplied; this preserves the sampled orientation for box/capsule.
		sampleParams.CFrame = cf
		table.insert(poses, { Parameters = sampleParams, Traveled = traveled })
	end
	return poses
end

-- Id-sorted timelines visible to the context whose history may meet any pose.
local function candidatesFor(context, params, poses)
	local min, max
	for _, pose in ipairs(poses) do
		local poseMin, poseMax = poseBounds(params.Shape, pose.Parameters)
		if not poseMin then
			min, max = nil, nil
			break
		end
		min = min and Vector3.new(math.min(min.X, poseMin.X), math.min(min.Y, poseMin.Y), math.min(min.Z, poseMin.Z))
			or poseMin
		max = max and Vector3.new(math.max(max.X, poseMax.X), math.max(max.Y, poseMax.Y), math.max(max.Z, poseMax.Z))
			or poseMax
	end
	local timelines = context:_candidates(min, max)
	if params.Filter then
		local filtered = {}
		for _, timeline in ipairs(timelines) do
			if params.Filter(timeline) then
				table.insert(filtered, timeline)
			end
		end
		timelines = filtered
	end
	return timelines
end

local function hitFor(context, timeline, queryParameters, shape)
	local state = context:getState(timeline)
	local definition = state and context:getCollision(timeline)
	if not definition then
		return nil
	end
	local hit = queryOne(queryParameters, Collision.toWorldSpace(definition, state.Transform.CFrame), timeline, shape)
	return hit.Hit and hit or nil
end

-- Lowest internal Distance at one pose. For rays that is travel; for volumes it is a
-- shape-pair separation metric used only for legacy Query results and tie ranking.
local function nearestAt(context, timelines, queryParameters, shape)
	local best
	for _, timeline in ipairs(timelines) do
		local hit = hitFor(context, timeline, queryParameters, shape)
		if hit and (not best or hit.Distance < best.Distance) then
			best = hit
		end
	end
	return best
end

-- First hit along the poses, with cumulative chord travel to it.
local function firstAlong(context, timelines, poses, shape)
	local best, bestTravel = nil, math.huge
	for _, pose in ipairs(poses) do
		-- Ray travel is never negative, so no later pose can beat an earlier best here.
		if best and pose.Traveled >= bestTravel then
			break
		end
		local hit = nearestAt(context, timelines, pose.Parameters, shape)
		if hit then
			local travel = pose.Traveled + (shape == "Ray" and hit.Distance or 0)
			if travel < bestTravel then
				best, bestTravel = hit, travel
			end
			if shape ~= "Ray" then
				break
			end
		end
	end
	return best, bestTravel
end

--- Directed query: the first target hit by a ray, or by a volume swept along a Path.
--- Distance is exact ray travel, or approximate cumulative chord travel along a Path.
--- @return CastResult? - nil when nothing is hit
function QueryEngine.cast(context, params)
	validate(params, "Cast")
	local shape = params.Shape
	assert(
		shape == "Ray" or params.Path,
		"Cast with a " .. shape .. " requires a Path; use Overlap for a static volume"
	)
	local poses = posesFor(params)
	local best, travel = firstAlong(context, candidatesFor(context, params, poses), poses, shape)
	if not best then
		return nil
	end
	return table.freeze({
		Timeline = best.Timeline,
		Distance = travel,
		Position = best.Position,
		Normal = best.Normal,
		Name = best.Name,
	})
end

--- Volume query: every target intersecting the volume (at any sampled pose with a Path),
--- one representative contact each from its earliest overlapping pose, sorted by Timeline Id.
--- @return { OverlapResult } - empty when nothing overlaps
function QueryEngine.overlap(context, params)
	validate(params, "Overlap")
	local shape = params.Shape
	assert(shape ~= "Ray", "Overlap requires a volume Shape; use Cast for rays")
	local poses = posesFor(params)
	local timelines = candidatesFor(context, params, poses)
	local found, results = {}, {}
	for _, pose in ipairs(poses) do
		for _, timeline in ipairs(timelines) do
			if not found[timeline] then
				local hit = hitFor(context, timeline, pose.Parameters, shape)
				if hit then
					found[timeline] = true
					table.insert(
						results,
						table.freeze({
							Timeline = timeline,
							Position = hit.Position,
							Normal = hit.Normal,
							Name = hit.Name,
						})
					)
				end
			end
		end
	end
	table.sort(results, function(a, b)
		return a.Timeline.Id < b.Timeline.Id
	end)
	return table.freeze(results)
end

--- Deprecated single-result query, kept for compatibility. Distance is ray travel, path
--- travel, or (static volumes) a shape-pair separation metric. Misses return { Hit = false }.
function QueryEngine.execute(context, params)
	local shape = params.Shape
	assert(targetHandlers[shape], "Unsupported query shape: " .. tostring(shape))
	local poses = posesFor(params)
	local timelines = candidatesFor(context, params, poses)
	if not params.Path then
		return nearestAt(context, timelines, params.Parameters, shape) or miss()
	end
	local best, travel = firstAlong(context, timelines, poses, shape)
	if not best then
		return miss()
	end
	best.Distance = travel
	return best
end
return QueryEngine
