-- Callable Roblox ModuleScript geometry checks.
-- Run with: require(game.ServerStorage.ChronocastTests["Geometry.spec"])()
local Chronocast = require(game.ReplicatedStorage.Chronocast)
local QueryEngine = require(game.ReplicatedStorage.Chronocast.Query)

return function()
	local collision = Chronocast.Collision
	local function assertHit(result, label)
		assert(result and result.Hit, label .. " should hit")
		assert(result.Position and result.Normal and result.Distance ~= nil, label .. " should return contact geometry")
	end
	local function assertMiss(result, label)
		assert(result and not result.Hit, label .. " should miss")
	end
	local function isolatedQuery(shape, parameters, definition)
		local timeline = { Id = "isolated" }
		local context = {
			_candidates = function()
				return { timeline }
			end,
			getState = function()
				return { Transform = { CFrame = CFrame.new() } }
			end,
			getCollision = function()
				return definition
			end,
		}
		return QueryEngine.execute(context, { Shape = shape, Parameters = parameters })
	end

	-- All twelve supported query-shape / historical-collision-shape pairs,
	-- each against a one-timeline mock so another hit cannot mask the case.
	local targetDefinitions = {
		Box = collision.Box({ Offset = CFrame.new(5, 0, 0), Size = Vector3.new(2, 2, 2) }),
		Sphere = collision.Sphere({ Offset = CFrame.new(5, 0, 0), Radius = 1 }),
		Capsule = collision.Capsule({ Offset = CFrame.new(5, 0, 0), Radius = 1, Height = 2 }),
	}
	local queryParameters = {
		Ray = { Origin = Vector3.zero, Direction = Vector3.xAxis, MaxDistance = 10 },
		Sphere = { Origin = Vector3.new(4, 0, 0), Radius = 1 },
		Box = { Origin = Vector3.new(5, 0, 0), Size = Vector3.new(1, 1, 1) },
		Capsule = { Origin = Vector3.new(5, 0, 0), Radius = 0.5, Height = 2 },
	}
	for _, queryShape in ipairs({ "Ray", "Sphere", "Box", "Capsule" }) do
		for _, targetShape in ipairs({ "Box", "Sphere", "Capsule" }) do
			assertHit(
				isolatedQuery(queryShape, queryParameters[queryShape], targetDefinitions[targetShape]),
				queryShape .. "/" .. targetShape
			)
		end
	end
	-- Every overlap returns a representative point on the historical target,
	-- with its outward normal (not a point/normal on the query volume).
	for _, shape in ipairs({ "Sphere", "Box", "Capsule" }) do
		local parameters = { Origin = Vector3.new(3.5, 0, 0), Radius = 1, Height = 2, Size = Vector3.new(2, 2, 2) }
		for _, targetShape in ipairs({ "Box", "Sphere", "Capsule" }) do
			local hit = isolatedQuery(shape, parameters, targetDefinitions[targetShape])
			assertHit(hit, shape .. "/" .. targetShape .. " contact")
			assert(math.abs(hit.Position.X - 4) < 1e-4, "contact must lie on target's left surface")
			assert((hit.Normal + Vector3.xAxis).Magnitude < 1e-4, "normal must face out of target toward query")
		end
	end
	assertMiss(
		isolatedQuery(
			"Ray",
			{ Origin = Vector3.zero, Direction = -Vector3.xAxis, MaxDistance = 10 },
			targetDefinitions.Box
		),
		"box wholly behind ray"
	)
	assertHit(
		isolatedQuery("Capsule", { Origin = Vector3.new(6, 0, 0), Radius = 0, Height = 0 }, targetDefinitions.Box),
		"zero-radius capsule tangent at endpoint"
	)
	for _, targetShape in ipairs({ "Box", "Sphere", "Capsule" }) do
		local inside = isolatedQuery(
			"Ray",
			{ Origin = Vector3.new(5, 0, 0), Direction = Vector3.xAxis, MaxDistance = 10 },
			targetDefinitions[targetShape]
		)
		assertHit(inside, "inside ray/" .. targetShape)
		assert(inside.Distance == 0, "inside ray should report zero travel")
	end

	-- The world AABBs overlap, but the OBBs are separated along their local axes.
	local queryBoxCF = CFrame.new(30, 0, 0) * CFrame.Angles(0, 0, math.pi / 6)
	local targetBox = collision.Box({
		Offset = CFrame.new(30, 0, 2.64) * CFrame.Angles(0, 0, -math.pi / 6),
		Size = Vector3.new(5, 0.2, 0.2),
	})
	local satContext = {
		_candidates = function()
			return { { Id = "sat" } }
		end,
		getState = function()
			return { Transform = { CFrame = CFrame.new() } }
		end,
		getCollision = function()
			return targetBox
		end,
	}
	assertMiss(
		QueryEngine.execute(satContext, {
			Shape = "Box",
			Parameters = { CFrame = queryBoxCF, Origin = queryBoxCF.Position, Size = Vector3.new(5, 0.2, 0.2) },
		}),
		"separated oriented box SAT"
	)

	local part = Instance.new("Part")
	part.Size = Vector3.new(2, 4, 6)
	part.CFrame = CFrame.new(10, 0, 0)
	local fromPart = collision.FromPart(part, CFrame.new(8, 0, 0))
	assert(
		(fromPart.Offset.Position - Vector3.new(2, 0, 0)).Magnitude < 1e-5,
		"FromPart offset should be relative to reference"
	)
	assert(table.isfrozen(fromPart), "generated collision should be frozen")
	part:Destroy()
	local meshPart = Instance.new("MeshPart")
	meshPart.Size = Vector3.new(2, 2, 2)
	assert(collision.FromPart(meshPart).Shape == "Box", "BaseParts without Shape should use a safe box fallback")
	meshPart:Destroy()

	local reference = CFrame.new(20, 3, 1) * CFrame.Angles(0, math.pi / 2, 0)
	local model = Instance.new("Model")
	local modelPart = Instance.new("Part")
	modelPart.Size = Vector3.new(2, 2, 2)
	modelPart.CFrame = reference * CFrame.new(3, 0, 0)
	modelPart.Parent = model
	local fromModel = collision.FromModel(model, reference)
	assert(
		(fromModel.Offset.Position - Vector3.new(3, 0, 0)).Magnitude < 1e-4,
		"FromModel bounds should use reference-local coordinates"
	)
	model:Destroy()

	local cylinder = Instance.new("Part")
	cylinder.Shape = Enum.PartType.Cylinder
	cylinder.Size = Vector3.new(4, 2, 2)
	cylinder.CFrame = CFrame.new(5, 0, 0)
	local cylinderCollision = collision.FromPart(cylinder)
	assert(cylinderCollision.Shape == "Box", "cylinder should use conservative oriented bounds")
	local cylinderHit = isolatedQuery(
		"Ray",
		{ Origin = Vector3.new(-5, 0, 0), Direction = Vector3.xAxis, MaxDistance = 10 },
		cylinderCollision
	)
	assertHit(cylinderHit, "ray along cylinder axis")
	assert(math.abs(cylinderHit.Distance - 3) < 1e-5, "generated collision must not protrude beyond cylinder end")
	cylinder:Destroy()

	local line = Chronocast.Path.Line({ Start = Vector3.zero, End = Vector3.new(3, 4, 0) })
	assert(line:Length() == 5, "Line:Length() should return path length")
	assert(type(line.Length) == "function", "Line.Length should remain callable")
	local id = "GeometrySpec_" .. tostring(math.floor(os.clock() * 1000000))
	Chronocast:Track({
		Id = id,
		Collision = targetDefinitions.Box,
		Adapter = {
			GetTransform = function()
				return CFrame.new()
			end,
		},
	})
	local context = Chronocast:CreateContext(Chronocast:GetServerTime())
	local function query(shape, parameters, path)
		return context:Query({
			Shape = shape,
			Parameters = parameters,
			Path = path,
			Filter = function(timeline)
				return timeline.Id == id
			end,
		})
	end
	local ok, err = pcall(function()
		local hit = query("Ray", { Origin = Vector3.zero, Direction = Vector3.xAxis, MaxDistance = 10 })
		assertHit(hit, "context historical ray")
		assert(hit.Distance == 4, "ray/box first contact distance should be exact")

		local linePath = Chronocast.Path.Line({ Start = Vector3.zero, End = Vector3.new(10, 0, 0), Samples = 10 })
		local lineHit = query("Sphere", { Radius = 0.5 }, linePath)
		assertHit(lineHit, "Line path hit")
		assert(math.abs(lineHit.Distance - 4) < 1e-4, "Line path should report earliest travel distance")

		-- No Length member: path distance must be accumulated from sampled chords.
		local curvedPath = Chronocast.Path.Custom({
			Samples = 2,
			Sample = function(_, alpha)
				local point = alpha < 0.5 and Vector3.new(alpha * 6, alpha * 8, 0)
					or Vector3.new(3 + (alpha - 0.5) * 6, 4 - (alpha - 0.5) * 8, 0)
				return CFrame.new(point)
			end,
		})
		local curvedHit = query("Sphere", { Radius = 0.5 }, curvedPath)
		assertHit(curvedHit, "custom curved path hit")
		assert(math.abs(curvedHit.Distance - 10) < 1e-4, "custom curve should use accumulated chord distance")
		assert(not pcall(function()
			query(
				"Sphere",
				{ Radius = 0.5 },
				Chronocast.Path.Custom({
					Samples = math.huge,
					Sample = function()
						return CFrame.new()
					end,
				})
			)
		end), "non-finite sample count should be rejected")
	end)
	context:Destroy()
	Chronocast:Untrack(id)
	if not ok then
		error(err, 0)
	end
end
