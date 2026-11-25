-- Chronocast v2 - Utility Functions

local Utils = {}

--- Linear interpolation between two values.
--- @param a number
--- @param b number
--- @param t number (0..1)
--- @return number
function Utils.lerp(a, b, t)
	return a + (b - a) * t
end

--- Spherical linear interpolation between two CFrames (rotation only).
--- Uses quaternion SLERP for rotation.
--- @param a CFrame
--- @param b CFrame
--- @param t number (0..1)
--- @return CFrame
function Utils.slerp(a, b, t)
	local ax, ay, az, a00, a01, a02, a10, a11, a12, a20, a21, a22 = a:GetComponents()
	local bx, by, bz, b00, b01, b02, b10, b11, b12, b20, b21, b22 = b:GetComponents()

	-- Extract position
	local posA = Vector3.new(ax, ay, az)
	local posB = Vector3.new(bx, by, bz)

	-- Build rotation matrices
	local ra = CFrame.new(0, 0, 0, a00, a01, a02, a10, a11, a12, a20, a21, a22)
	local rb = CFrame.new(0, 0, 0, b00, b01, b02, b10, b11, b12, b20, b21, b22)

	-- Convert to quaternions
	local qa = Utils.cframeToQuaternion(ra)
	local qb = Utils.cframeToQuaternion(rb)

	-- SLERP the quaternions
	local q = Utils.quaternionSlerp(qa, qb, t)

	-- Interpolate position
	local pos = posA:Lerp(posB, t)

	-- Convert quaternion back to CFrame
	local rot = Utils.quaternionToCFrame(q)

	return CFrame.new(pos.X, pos.Y, pos.Z) * rot
end

--- Converts a CFrame to a quaternion {x, y, z, w}.
--- @param cf CFrame
--- @return table
function Utils.cframeToQuaternion(cf)
	local _, _, _, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cf:GetComponents()

	local trace = m00 + m11 + m22
	local q = { x = 0, y = 0, z = 0, w = 1 }

	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		q.w = 0.25 * s
		q.x = (m21 - m12) / s
		q.y = (m02 - m20) / s
		q.z = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		q.w = (m21 - m12) / s
		q.x = 0.25 * s
		q.y = (m01 + m10) / s
		q.z = (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		q.w = (m02 - m20) / s
		q.x = (m01 + m10) / s
		q.y = 0.25 * s
		q.z = (m12 + m21) / s
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		q.w = (m10 - m01) / s
		q.x = (m02 + m20) / s
		q.y = (m12 + m21) / s
		q.z = 0.25 * s
	end

	return q
end

--- Converts a quaternion {x, y, z, w} to a CFrame rotation.
--- @param q table
--- @return CFrame
function Utils.quaternionToCFrame(q)
	local x, y, z, w = q.x, q.y, q.z, q.w
	local xx, yy, zz = x * x, y * y, z * z
	local xy, xz, yz = x * y, x * z, y * z
	local wx, wy, wz = w * x, w * y, w * z

	local m00 = 1 - 2 * (yy + zz)
	local m01 = 2 * (xy - wz)
	local m02 = 2 * (xz + wy)
	local m10 = 2 * (xy + wz)
	local m11 = 1 - 2 * (xx + zz)
	local m12 = 2 * (yz - wx)
	local m20 = 2 * (xz - wy)
	local m21 = 2 * (yz + wx)
	local m22 = 1 - 2 * (xx + yy)

	return CFrame.new(0, 0, 0, m00, m01, m02, m10, m11, m12, m20, m21, m22)
end

--- Spherical linear interpolation between two quaternions.
--- @param a table {x, y, z, w}
--- @param b table {x, y, z, w}
--- @param t number (0..1)
--- @return table
function Utils.quaternionSlerp(a, b, t)
	local cosOmega = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
	local qb = b

	if cosOmega < 0 then
		cosOmega = -cosOmega
		qb = { x = -b.x, y = -b.y, z = -b.z, w = -b.w }
	end

	local omega = math.acos(math.max(-1, math.min(1, cosOmega)))
	local sinOmega = math.sin(omega)

	if sinOmega < 0.0001 then
		return {
			x = Utils.lerp(a.x, qb.x, t),
			y = Utils.lerp(a.y, qb.y, t),
			z = Utils.lerp(a.z, qb.z, t),
			w = Utils.lerp(a.w, qb.w, t),
		}
	end

	local scaleA = math.sin((1 - t) * omega) / sinOmega
	local scaleB = math.sin(t * omega) / sinOmega

	return {
		x = scaleA * a.x + scaleB * qb.x,
		y = scaleA * a.y + scaleB * qb.y,
		z = scaleA * a.z + scaleB * qb.z,
		w = scaleA * a.w + scaleB * qb.w,
	}
end

--- Clamps a value between min and max.
--- @param value number
--- @param min number
--- @param max number
--- @return number
function Utils.clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

return Utils
