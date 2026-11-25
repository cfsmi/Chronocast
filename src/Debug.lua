-- Opt-in debug drawing for historical collision and queries.
-- Draws HandleAdornments in world space (adorned to Terrain by default), so no
-- physical parts are created. Nothing here is used by core query paths.
local Collision = require(script.Parent.Collision)

local Debug = {}

local Visualizer = {}
Visualizer.__index = Visualizer

local DEFAULTS = {
	Color = Color3.fromRGB(80, 170, 255),
	QueryColor = Color3.fromRGB(255, 200, 60),
	HitColor = Color3.fromRGB(255, 70, 70),
	Transparency = 0.6,
	Lifetime = nil, -- seconds; nil keeps drawings until Clear
}

--- Creates a visualizer that owns one Folder of adornments.
--- @param options { Parent: Instance?, Adornee: Instance?, Name: string?, Color: Color3?, QueryColor: Color3?, HitColor: Color3?, Transparency: number?, Lifetime: number? }?
function Debug.Visualizer(options)
	options = options or {}
	local folder = Instance.new("Folder")
	folder.Name = options.Name or "ChronocastDebug"
	folder.Parent = options.Parent or workspace
	local self = setmetatable({
		Folder = folder,
		Adornee = options.Adornee or workspace.Terrain,
		Color = options.Color or DEFAULTS.Color,
		QueryColor = options.QueryColor or DEFAULTS.QueryColor,
		HitColor = options.HitColor or DEFAULTS.HitColor,
		Transparency = options.Transparency or DEFAULTS.Transparency,
		Lifetime = options.Lifetime or DEFAULTS.Lifetime,
	}, Visualizer)
	return self
end

function Visualizer:_adorn(className, cframe, color, transparency, properties)
	local adornment = Instance.new(className)
	adornment.Adornee = self.Adornee
	adornment.CFrame = cframe
	adornment.Color3 = color
	adornment.Transparency = transparency or self.Transparency
	adornment.AlwaysOnTop = true
	adornment.ZIndex = 1
	for key, value in pairs(properties) do
		adornment[key] = value
	end
	adornment.Parent = self.Folder
	if self.Lifetime then
		task.delay(self.Lifetime, function()
			adornment:Destroy()
		end)
	end
	return adornment
end

-- Thin box from a to b: boxes are centered, so orientation along the segment is unambiguous.
function Visualizer:_segment(a, b, color, thickness)
	local length = (b - a).Magnitude
	if length <= 1e-6 then
		return
	end
	self:_adorn(
		"BoxHandleAdornment",
		CFrame.lookAt((a + b) / 2, b),
		color,
		0,
		{ Size = Vector3.new(thickness or 0.08, thickness or 0.08, length) }
	)
end

function Visualizer:_point(position, color, radius)
	self:_adorn("SphereHandleAdornment", CFrame.new(position), color, 0, { Radius = radius or 0.2 })
end

--- Draws a world-space collision definition (any shape, including compounds).
function Visualizer:DrawWorldCollision(definition, color, transparency)
	color = color or self.Color
	local shape = definition.Shape
	if shape == "Compound" then
		for _, child in ipairs(definition.Children) do
			self:DrawWorldCollision(child, color, transparency)
		end
	elseif shape == "Box" then
		self:_adorn("BoxHandleAdornment", definition.Offset, color, transparency, { Size = definition.Size })
	elseif shape == "Sphere" then
		self:_adorn("SphereHandleAdornment", definition.Offset, color, transparency, { Radius = definition.Radius })
	elseif shape == "Capsule" then
		-- Capsule axis is the Offset's UpVector; cylinder adornments extend along Z.
		self:_adorn(
			"CylinderHandleAdornment",
			definition.Offset * CFrame.Angles(math.pi / 2, 0, 0),
			color,
			transparency,
			{ Radius = definition.Radius, Height = definition.Height }
		)
		local half = definition.Offset.UpVector * (definition.Height / 2)
		for _, center in ipairs({ definition.Offset.Position + half, definition.Offset.Position - half }) do
			self:_adorn(
				"SphereHandleAdornment",
				CFrame.new(center),
				color,
				transparency,
				{ Radius = definition.Radius }
			)
		end
	end
end

--- Draws a timeline's reconstructed collision at a time (or a Context's time).
--- @param timeline Timeline
--- @param at number | Context
function Visualizer:DrawTimeline(timeline, at, color, transparency)
	local state
	if type(at) == "number" then
		state = timeline:GetState(at)
	else
		state = at:GetState(timeline)
	end
	if state and state.Collision then
		self:DrawWorldCollision(Collision.toWorldSpace(state.Collision, state.Transform.CFrame), color, transparency)
	end
	return state
end

--- Draws every timeline visible to a Context at its time.
function Visualizer:DrawContext(context, color)
	for _, timeline in ipairs(context:_candidates()) do
		self:DrawTimeline(timeline, context, color)
	end
end

--- Draws ghost poses through a timeline's retained history, fading toward the past.
--- @param options { From: number?, To: number?, Step: number? }?
function Visualizer:DrawTrail(timeline, options)
	options = options or {}
	local snapshots = timeline:GetSnapshots()
	if #snapshots == 0 then
		return
	end
	local from = options.From or snapshots[1].Time
	local to = options.To or snapshots[#snapshots].Time
	local step = options.Step or math.max((to - from) / 10, 1e-3)
	local count = math.floor((to - from) / step + 1e-9)
	for i = 0, count do
		local time = from + i * step
		local fade = count > 0 and i / count or 1
		self:DrawTimeline(timeline, time, nil, 1 - (1 - self.Transparency) * (0.25 + 0.75 * fade))
	end
end

--- Draws a Cast query (ray, or sampled path poses) and its result.
--- Pass the Context (or time) as `at` to also highlight the hit target's historical collision.
function Visualizer:DrawCast(params, result, at)
	local p = params.Parameters
	if params.Path then
		local samples = params.Path.Intervals or params.Path.Samples or 10
		local previous
		for i = 0, samples do
			local cf = params.Path:Sample(i / samples)
			if previous then
				self:_segment(previous, cf.Position, self.QueryColor)
			end
			previous = cf.Position
			if params.Shape ~= "Ray" then
				local pose = table.clone(p)
				pose.Origin, pose.CFrame = cf.Position, cf
				self:_drawQueryVolume(params.Shape, pose, 0.85)
			end
		end
	elseif params.Shape == "Ray" then
		local length = result and result.Distance
			or (p.MaxDistance and p.MaxDistance < math.huge and p.MaxDistance or 100)
		self:_segment(p.Origin, p.Origin + p.Direction.Unit * length, self.QueryColor)
	end
	if result then
		self:_point(result.Position, self.HitColor)
		self:_segment(result.Position, result.Position + result.Normal * 1.5, self.HitColor)
		if at then
			self:DrawTimeline(result.Timeline, at, self.HitColor)
		end
	end
end

function Visualizer:_drawQueryVolume(shape, p, transparency)
	local frame = p.CFrame or CFrame.new(p.Origin)
	if shape == "Sphere" then
		self:DrawWorldCollision(
			{ Shape = "Sphere", Offset = CFrame.new(p.Origin), Radius = p.Radius },
			self.QueryColor,
			transparency
		)
	elseif shape == "Box" then
		self:DrawWorldCollision({ Shape = "Box", Offset = frame, Size = p.Size }, self.QueryColor, transparency)
	elseif shape == "Capsule" then
		self:DrawWorldCollision(
			{ Shape = "Capsule", Offset = frame, Radius = p.Radius, Height = p.Height },
			self.QueryColor,
			transparency
		)
	end
end

--- Draws an Overlap query volume and each representative contact.
function Visualizer:DrawOverlap(params, results)
	if not params.Path then
		self:_drawQueryVolume(params.Shape, params.Parameters)
	end
	for _, hit in ipairs(results or {}) do
		self:_point(hit.Position, self.HitColor)
		self:_segment(hit.Position, hit.Position + hit.Normal * 1.5, self.HitColor)
	end
end

--- Removes every drawing.
function Visualizer:Clear()
	self.Folder:ClearAllChildren()
end

function Visualizer:Destroy()
	self.Folder:Destroy()
end

return Debug
