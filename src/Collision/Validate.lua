-- Structural validation for collision definitions, shared by the constructors and
-- by timelines when they accept or sample a definition.

local function finiteNonNegative(value)
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

--- @param definition CollisionDef
--- @return CollisionDef
local function validate(definition)
	assert(type(definition) == "table", "Collision definition must be a table")
	local shape = definition.Shape
	assert(typeof(definition.Offset) == "CFrame", "Collision Offset must be a CFrame")
	assert(definition.Name == nil or type(definition.Name) == "string", "Collision Name must be a string")
	if shape == "Box" then
		local size = definition.Size
		assert(
			typeof(size) == "Vector3"
				and finiteNonNegative(size.X)
				and finiteNonNegative(size.Y)
				and finiteNonNegative(size.Z),
			"Box Size must be a finite non-negative Vector3"
		)
	elseif shape == "Sphere" then
		assert(finiteNonNegative(definition.Radius), "Sphere Radius must be finite and non-negative")
	elseif shape == "Capsule" then
		assert(finiteNonNegative(definition.Radius), "Capsule Radius must be finite and non-negative")
		assert(finiteNonNegative(definition.Height), "Capsule Height must be finite and non-negative")
	elseif shape == "Compound" then
		assert(type(definition.Children) == "table" and #definition.Children > 0, "Compound requires children")
		for _, child in ipairs(definition.Children) do
			assert(type(child) == "table" and child.Shape ~= "Compound", "Compound children must be primitive shapes")
			validate(child)
		end
	else
		error("Invalid collision shape: " .. tostring(shape), 2)
	end
	return definition
end

return validate
