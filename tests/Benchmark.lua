-- Not a regression suite: prints timings for N tracked timelines.
-- Studio (server Command Bar, during Play): require(game.ServerStorage.ChronocastTests.Benchmark)()
-- Headless: lune run tools/headless.luau --bench
-- Captures use explicit future times and never yield, so Heartbeat cannot interleave.
return function(options)
	options = options or {}
	local Chronocast = require(game.ReplicatedStorage.Chronocast)
	local sizes = options.Sizes or { 50, 200, 1000 }
	local frames = options.Frames or 60
	local queries = options.Queries or 300
	local worldSize = options.WorldSize or 2000

	local seed = 42
	local function random()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local function range(lo, hi)
		return lo + (hi - lo) * random()
	end

	local lines = {}
	for _, count in ipairs(sizes) do
		local timelines, adapters = {}, {}
		local ok, err = xpcall(function()
			for i = 1, count do
				local adapter = {
					CFrame = CFrame.new(range(-worldSize / 2, worldSize / 2), 3, range(-worldSize / 2, worldSize / 2)),
				}
				function adapter:GetTransform()
					return self.CFrame
				end
				adapters[i] = adapter
				timelines[i] = Chronocast:Track({
					Id = string.format("__Bench_%05d", i),
					Adapter = adapter,
					Collision = Chronocast.Collision.Capsule({ Radius = 1, Height = 3 }),
					SnapshotInterval = 1 / 30,
					HistoryDuration = 1,
				})
			end
			local base = Chronocast:GetServerTime() + 100
			local step = 0.034 -- just over 1/30 so float error never trips the capture interval
			local captureStart = os.clock()
			for frame = 1, frames do
				for i = 1, count do
					local adapter = adapters[i]
					adapter.CFrame = adapter.CFrame + Vector3.new(0.4, 0, 0.3)
					timelines[i]:captureSnapshot(base + frame * step)
				end
			end
			local captureMs = (os.clock() - captureStart) / frames * 1000
			local time = base + frames * step * 0.6

			local function timeQueries(build, run)
				local params = {}
				for q = 1, queries do
					params[q] = build(q)
				end
				local start = os.clock()
				local hits = 0
				for q = 1, queries do
					local context = Chronocast:CreateContext(time)
					if run(context, params[q]) then
						hits += 1
					end
					context:Destroy()
				end
				return (os.clock() - start) / queries * 1e6, hits
			end
			local function rayParams(maxDistance)
				return function()
					local origin =
						Vector3.new(range(-worldSize / 2, worldSize / 2), 3, range(-worldSize / 2, worldSize / 2))
					local angle = range(0, math.pi * 2)
					return {
						Shape = "Ray",
						Parameters = {
							Origin = origin,
							Direction = Vector3.new(math.cos(angle), 0, math.sin(angle)),
							MaxDistance = maxDistance,
						},
					}
				end
			end
			local cast = function(context, p)
				return context:Cast(p) ~= nil
			end
			local indexedUs, indexedHits = timeQueries(rayParams(150), cast)
			local scanUs, scanHits = timeQueries(rayParams(nil), cast)
			local overlapUs, overlapHits = timeQueries(function()
				return {
					Shape = "Sphere",
					Parameters = {
						Origin = Vector3.new(
							range(-worldSize / 2, worldSize / 2),
							3,
							range(-worldSize / 2, worldSize / 2)
						),
						Radius = 25,
					},
				}
			end, function(context, p)
				return #context:Overlap(p) > 0
			end)

			table.insert(
				lines,
				string.format(
					"N=%-5d capture %7.3f ms/frame | ray 150 studs (indexed) %8.1f us [%d hits] | ray unbounded (full scan) %8.1f us [%d hits] | sphere r=25 overlap %8.1f us [%d hits]",
					count,
					captureMs,
					indexedUs,
					indexedHits,
					scanUs,
					scanHits,
					overlapUs,
					overlapHits
				)
			)
		end, debug.traceback)
		for _, timeline in ipairs(timelines) do
			timeline:Destroy()
		end
		if not ok then
			error(err, 0)
		end
	end
	for _, line in ipairs(lines) do
		print(line)
	end
	return lines
end
