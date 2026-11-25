-- Chronocast v2 - Custom Collision
--
-- Allows developers to construct custom collision definitions manually.

local Custom = {}

--- Creates a custom collision definition.
--- @param collisionDef CollisionDef
--- @return CollisionDef
function Custom.create(collisionDef)
	assert(collisionDef, "Custom.create requires a collision definition")
	assert(collisionDef.Shape, "Collision definition requires a Shape")

	-- Validate shape
	local validShapes = { Box = true, Sphere = true, Capsule = true }
	assert(validShapes[collisionDef.Shape], "Invalid collision shape: " .. tostring(collisionDef.Shape))

	return table.freeze({
		Shape = collisionDef.Shape,
		Offset = collisionDef.Offset or CFrame.new(),
		Size = collisionDef.Size,
		Radius = collisionDef.Radius,
		Height = collisionDef.Height,
	})
end

return Custom