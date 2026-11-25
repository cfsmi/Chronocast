-- Cast/Overlap contracts, validation, compound targets and collision providers.
return function()
	local Chronocast = require(game.ReplicatedStorage.Chronocast)
	local C = Chronocast.Collision
	local ids, mine = {}, {}
	local function track(name, cframe, collision, extra)
		local config = {
			Id = "__Query_" .. name,
			Collision = collision,
			Adapter = {
				GetTransform = function()
					return cframe
				end,
			},
		}
		for key, value in pairs(extra or {}) do
			config[key] = value
		end
		local timeline = Chronocast:Track(config)
		table.insert(ids, timeline.Id)
		mine[timeline] = true
		return timeline
	end
	local function onlyMine(timeline)
		return mine[timeline] == true
	end

	local ok, err = xpcall(function()
		local a = track("A", CFrame.new(5, 0, 0), C.Box({ Size = Vector3.new(2, 2, 2) }))
		local b = track("B", CFrame.new(9, 0, 0), C.Sphere({ Radius = 1 }))
		local context = Chronocast:CreateContext(Chronocast:GetServerTime())
		local function ray(origin, direction, maxDistance)
			return {
				Shape = "Ray",
				Parameters = { Origin = origin, Direction = direction, MaxDistance = maxDistance },
				Filter = onlyMine,
			}
		end

		-- Cast: one frozen nearest hit with exact travel, or nil.
		local hit = context:Cast(ray(Vector3.zero, Vector3.xAxis, 20))
		assert(hit and hit.Timeline == a and hit.Distance == 4 and hit.Hit == nil, "Cast should return the first hit")
		assert(table.isfrozen(hit), "Cast results must be frozen")
		assert(context:Cast(ray(Vector3.zero, -Vector3.xAxis, 20)) == nil, "Cast miss must be nil")
		assert(context:Cast(ray(Vector3.zero, Vector3.xAxis, 3)) == nil, "MaxDistance must bound Cast")

		-- Overlap: every intersecting target, Id-sorted, without Distance.
		local overlaps = context:Overlap({
			Shape = "Box",
			Parameters = { Origin = Vector3.new(7, 0, 0), Size = Vector3.new(6, 2, 2) },
			Filter = onlyMine,
		})
		assert(
			#overlaps == 2 and overlaps[1].Timeline == a and overlaps[2].Timeline == b,
			"Overlap returns all targets by Id"
		)
		assert(
			overlaps[1].Distance == nil and table.isfrozen(overlaps) and table.isfrozen(overlaps[1]),
			"Overlap results are frozen, no Distance"
		)
		local empty = context:Overlap({
			Shape = "Sphere",
			Parameters = { Origin = Vector3.new(0, 50, 0), Radius = 1 },
			Filter = onlyMine,
		})
		assert(#empty == 0, "Overlap miss must be an empty array")

		-- Sampled paths: Cast reports chord travel to the first hitting pose; Overlap unions poses.
		local path = Chronocast.Path.Line({ Start = Vector3.zero, End = Vector3.new(20, 0, 0), Intervals = 20 })
		local swept = context:Cast({ Shape = "Sphere", Parameters = { Radius = 0.5 }, Path = path, Filter = onlyMine })
		assert(
			swept and swept.Timeline == a and math.abs(swept.Distance - 4) < 1e-4,
			"swept Cast should stop at the first hit"
		)
		local legacy =
			context:Query({ Shape = "Sphere", Parameters = { Radius = 0.5 }, Path = path, Filter = onlyMine })
		assert(
			legacy.Hit and legacy.Timeline == swept.Timeline and legacy.Distance == swept.Distance,
			"legacy Query path agrees"
		)
		local sweptOverlap =
			context:Overlap({ Shape = "Sphere", Parameters = { Radius = 0.5 }, Path = path, Filter = onlyMine })
		assert(#sweptOverlap == 2, "swept Overlap reports every target touched by any pose")
		local rayPath =
			Chronocast.Path.Line({ Start = Vector3.new(0, 0, -3), End = Vector3.new(0, 0, 3), Intervals = 6 })
		local rayAlong = context:Cast({
			Shape = "Ray",
			Parameters = { Direction = Vector3.xAxis, MaxDistance = 20 },
			Path = rayPath,
			Filter = onlyMine,
		})
		assert(rayAlong and math.abs(rayAlong.Distance - 6) < 1e-4, "ray paths add chord travel to ray travel (2 + 4)")

		-- Validation at the public seam.
		local function rejects(method, params, label)
			assert(not pcall(function()
				context[method](context, params)
			end), label)
		end
		rejects(
			"Cast",
			{ Shape = "Sphere", Parameters = { Origin = Vector3.zero, Radius = 1 } },
			"static volume Cast needs a Path"
		)
		rejects("Overlap", ray(Vector3.zero, Vector3.xAxis, 10), "Overlap rejects rays")
		rejects("Cast", ray(Vector3.zero, Vector3.zero, 10), "zero ray direction")
		rejects("Cast", ray(Vector3.new(0 / 0, 0, 0), Vector3.xAxis, 10), "NaN ray origin")
		rejects("Cast", ray(Vector3.zero, Vector3.xAxis, -1), "negative MaxDistance")
		rejects("Overlap", { Shape = "Sphere", Parameters = { Origin = Vector3.zero, Radius = -1 } }, "negative radius")
		rejects("Overlap", { Shape = "Box", Parameters = { Origin = Vector3.zero } }, "Box without Size")
		rejects("Overlap", { Shape = "Capsule", Parameters = { Radius = 1, Height = 2 } }, "Capsule without pose")
		rejects("Overlap", { Shape = "Cone", Parameters = {} }, "unknown shape")
		rejects(
			"Overlap",
			{ Shape = "Sphere", Parameters = { Origin = Vector3.zero, Radius = 1 }, Filter = true },
			"non-function Filter"
		)
		assert(context:Query(ray(Vector3.zero, -Vector3.xAxis, 20)).Hit == false, "legacy Query keeps { Hit = false }")
		context:Destroy()

		-- Compound targets report which named child was hit.
		local dummyCollision = C.Compound({
			C.Box({ Name = "Torso", Size = Vector3.new(2, 2, 1) }),
			C.Sphere({ Name = "Head", Offset = CFrame.new(0, 2, 0), Radius = 0.6 }),
		})
		local dummy = track("Dummy", CFrame.new(0, 0, -10), dummyCollision)
		local compoundContext = Chronocast:CreateContext(Chronocast:GetServerTime())
		local head = compoundContext:Cast(ray(Vector3.new(0, 2, 0), -Vector3.zAxis, 50))
		assert(
			head and head.Timeline == dummy and head.Name == "Head" and math.abs(head.Distance - 9.4) < 1e-5,
			"head hit"
		)
		local torso = compoundContext:Cast(ray(Vector3.zero, -Vector3.zAxis, 50))
		assert(torso and torso.Name == "Torso" and math.abs(torso.Distance - 9.5) < 1e-5, "torso hit")
		local touching = compoundContext:Overlap({
			Shape = "Sphere",
			Parameters = { Origin = Vector3.new(0, 2, -9), Radius = 0.5 },
			Filter = onlyMine,
		})
		assert(#touching == 1 and touching[1].Name == "Head", "Overlap reports the touched child")
		compoundContext:Destroy()
		assert(not pcall(C.Compound, { dummyCollision }), "nested compounds are rejected")
		assert(not pcall(C.Compound, {}), "empty compounds are rejected")
		assert(not pcall(C.Custom, { Shape = "Sphere", Radius = -1 }), "Custom validates fields")
		assert(not pcall(function()
			track("Invalid", CFrame.new(), { Shape = "Box", Offset = CFrame.new() })
		end), "Track rejects malformed collision")

		-- Collision providers are sampled per capture; history keeps each sampled shape.
		local radius = 1
		local provided = track("Provider", CFrame.new(0, 0, 30), function()
			return C.Sphere({ Radius = radius })
		end, { SnapshotInterval = 0.05 })
		local t1 = provided:GetSnapshots()[1].Time
		radius = 3
		provided:captureSnapshot(t1 + 1)
		local early, late = Chronocast:CreateContext(t1), Chronocast:CreateContext(t1 + 1)
		assert(
			early:GetCollision(provided).Radius == 1 and late:GetCollision(provided).Radius == 3,
			"provider output is sampled history"
		)
		early:Destroy()
		late:Destroy()
		radius = -1
		assert(not pcall(function()
			provided:captureSnapshot(t1 + 2)
		end), "invalid provider output fails the capture")
		provided:SetCollision(C.Box({ Size = Vector3.one }))
		assert(provided:captureSnapshot(t1 + 3), "SetCollision replaces a provider with a static definition")
	end, debug.traceback)
	for _, id in ipairs(ids) do
		Chronocast:Untrack(id)
	end
	if not ok then
		error(err, 0)
	end
end
