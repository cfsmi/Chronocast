-- Chronocast v2 - Collision Module
--
-- Immutable collision shapes and generation utilities.
-- Collision belongs to Timelines, not instances.

local Collision = {}

local FromModelModule = require(script.FromModel)
local FromPartModule = require(script.FromPart)
local FromCharacterModule = require(script.FromCharacter)
local CustomModule = require(script.Custom)
local Validate = require(script.Validate)

--- Asserts that a definition is well formed and returns it unchanged.
Collision.validate = Validate

--- Generates a collision definition from a Model.
--- @param model Model
--- @return CollisionDef
function Collision.FromModel(model, referenceCFrame)
	return FromModelModule.generate(model, referenceCFrame)
end

--- Generates a collision definition from a BasePart.
--- @param part BasePart
--- @return CollisionDef
function Collision.FromPart(part, referenceCFrame)
	return FromPartModule.generate(part, referenceCFrame)
end

--- Returns a collision provider that samples one named shape per character limb.
--- Pass it as a timeline's Collision; it runs on every capture.
--- @param character Model
--- @param options { IncludeAccessories: boolean?, Filter: ((BasePart) -> boolean)?, Reference: ((Model) -> CFrame)? }?
--- @return CollisionProvider
function Collision.FromCharacter(character, options)
	return FromCharacterModule.provider(character, options)
end

--- Creates a custom collision definition.
--- @param collisionDef CollisionDef
--- @return CollisionDef
function Collision.Custom(collisionDef)
	return CustomModule.create(collisionDef)
end

-- Shape type constants
Collision.Shapes = table.freeze({
	Box = "Box",
	Sphere = "Sphere",
	Capsule = "Capsule",
	Compound = "Compound",
})

--- Creates a Box collision definition.
--- @param params { Offset: CFrame?, Size: Vector3, Name: string? }
--- @return CollisionDef
function Collision.Box(params)
	return table.freeze({
		Shape = Collision.Shapes.Box,
		Offset = params.Offset or CFrame.new(),
		Size = params.Size or Vector3.new(1, 1, 1),
		Name = params.Name,
	})
end

--- Creates a Sphere collision definition.
--- @param params { Offset: CFrame?, Radius: number, Name: string? }
--- @return CollisionDef
function Collision.Sphere(params)
	return table.freeze({
		Shape = Collision.Shapes.Sphere,
		Offset = params.Offset or CFrame.new(),
		Radius = params.Radius or 0.5,
		Name = params.Name,
	})
end

--- Creates a Capsule collision definition.
--- @param params { Offset: CFrame?, Radius: number, Height: number, Name: string? }
--- @return CollisionDef
function Collision.Capsule(params)
	return table.freeze({
		Shape = Collision.Shapes.Capsule,
		Offset = params.Offset or CFrame.new(),
		Radius = params.Radius or 0.5,
		Height = params.Height or 2,
		Name = params.Name,
	})
end

--- Creates a Compound collision definition from primitive children.
--- Child offsets are local to the compound's Offset. Queries report the hit child's Name.
--- @param children { CollisionDef }
--- @param offset CFrame?
--- @return CollisionDef
function Collision.Compound(children, offset)
	assert(type(children) == "table" and #children > 0, "Compound requires a nonempty array of children")
	local copied = table.clone(children)
	for _, child in ipairs(copied) do
		assert(
			type(child) == "table" and child.Shape ~= Collision.Shapes.Compound,
			"Compound children must be primitive shapes"
		)
	end
	return Collision.validate(table.freeze({
		Shape = Collision.Shapes.Compound,
		Offset = offset or CFrame.new(),
		Children = table.freeze(copied),
	}))
end

--- Returns a radius around the definition's reference origin that contains the shape
--- under any rotation. The spatial index uses it to bound interpolated poses.
--- @param definition CollisionDef
--- @return number
function Collision.boundingRadius(definition)
	local reach = definition.Offset.Position.Magnitude
	local shape = definition.Shape
	if shape == "Box" then
		return reach + definition.Size.Magnitude / 2
	elseif shape == "Sphere" then
		return reach + definition.Radius
	elseif shape == "Capsule" then
		return reach + definition.Height / 2 + definition.Radius
	end
	local childReach = 0
	for _, child in ipairs(definition.Children) do
		childReach = math.max(childReach, Collision.boundingRadius(child))
	end
	return reach + childReach
end

--- Transforms a local-space collision definition into world space.
--- @param collisionDef CollisionDef
--- @param worldCFrame CFrame
--- @return CollisionDef
function Collision.toWorldSpace(collisionDef, worldCFrame)
	local result = table.clone(collisionDef)
	result.Offset = worldCFrame * collisionDef.Offset
	if collisionDef.Children then
		local children = {}
		for i, child in ipairs(collisionDef.Children) do
			children[i] = Collision.toWorldSpace(child, result.Offset)
		end
		result.Children = table.freeze(children)
	end
	return table.freeze(result)
end

return Collision
