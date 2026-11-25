-- Chronocast v2 - Collision Module
--
-- Immutable collision shapes and generation utilities.
-- Collision belongs to Timelines, not instances.

local Collision = {}

local FromModelModule = require(script.FromModel)
local FromPartModule = require(script.FromPart)
local CustomModule = require(script.Custom)

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
})

--- Creates a Box collision definition.
--- @param params { Offset: CFrame?, Size: Vector3 }
--- @return CollisionDef
function Collision.Box(params)
	return table.freeze({
		Shape = Collision.Shapes.Box,
		Offset = params.Offset or CFrame.new(),
		Size = params.Size or Vector3.new(1, 1, 1),
	})
end

--- Creates a Sphere collision definition.
--- @param params { Offset: CFrame?, Radius: number }
--- @return CollisionDef
function Collision.Sphere(params)
	return table.freeze({
		Shape = Collision.Shapes.Sphere,
		Offset = params.Offset or CFrame.new(),
		Radius = params.Radius or 0.5,
	})
end

--- Creates a Capsule collision definition.
--- @param params { Offset: CFrame?, Radius: number, Height: number }
--- @return CollisionDef
function Collision.Capsule(params)
	return table.freeze({
		Shape = Collision.Shapes.Capsule,
		Offset = params.Offset or CFrame.new(),
		Radius = params.Radius or 0.5,
		Height = params.Height or 2,
	})
end

--- Transforms a local-space collision definition into world space.
--- @param collisionDef CollisionDef
--- @param worldCFrame CFrame
--- @return CollisionDef
function Collision.toWorldSpace(collisionDef, worldCFrame)
	local result = {}
	for k, v in pairs(collisionDef) do
		result[k] = v
	end
	result.Offset = worldCFrame * collisionDef.Offset
	return table.freeze(result)
end

return Collision