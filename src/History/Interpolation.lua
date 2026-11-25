-- Chronocast v2 - Interpolation
--
-- Reconstructs historical state from snapshots using interpolation rules.
-- Supports position linear, rotation SLERP, velocity sampling.
-- No extrapolation by default.

local Utils = require(script.Parent.Parent.Utils)
local Immutable = require(script.Parent.Parent.Immutable)

local Interpolation = {}

--- Interpolates between two snapshots at a given time.
--- Uses the interpolation mode specified in config.
--- @param beforeSnapshot table - Snapshot before target time
--- @param afterSnapshot table - Snapshot after target time
--- @param targetTime number - The time to reconstruct
--- @param config table - Interpolation config
--- @return table - Reconstructed snapshot
function Interpolation.interpolate(beforeSnapshot, afterSnapshot, targetTime, config)
	if beforeSnapshot == afterSnapshot or beforeSnapshot == nil then
		return afterSnapshot or beforeSnapshot
	end

	if afterSnapshot == nil then
		return beforeSnapshot
	end

	-- Calculate interpolation factor
	local timeDelta = afterSnapshot.Time - beforeSnapshot.Time
	if timeDelta <= 0 then
		return beforeSnapshot
	end

	local alpha = (targetTime - beforeSnapshot.Time) / timeDelta
	alpha = math.clamp(alpha, 0, 1)

	config = config or {}
	local posMode = config.PositionMode or "Linear"
	local rotMode = config.RotationMode or "SLERP"
	local velMode = config.VelocityMode or "Sampled"

	local result = {
		Time = targetTime,
		Transform = beforeSnapshot.Transform,
		Velocity = beforeSnapshot.Velocity,
		AngularVelocity = beforeSnapshot.AngularVelocity,
		Metadata = beforeSnapshot.Metadata or {},
		Collision = beforeSnapshot.Collision,
	}

	-- Interpolate transform
	if posMode == "Linear" then
		result.Transform =
			Interpolation.lerpTransform(beforeSnapshot.Transform, afterSnapshot.Transform, alpha, rotMode)
	else
		-- Nearest: use closest snapshot
		if alpha < 0.5 then
			result.Transform = beforeSnapshot.Transform
		else
			result.Transform = afterSnapshot.Transform
		end
	end

	-- Interpolate velocity
	if velMode == "Interpolated" then
		if beforeSnapshot.Velocity and afterSnapshot.Velocity then
			result.Velocity = beforeSnapshot.Velocity:Lerp(afterSnapshot.Velocity, alpha)
		end
		if beforeSnapshot.AngularVelocity and afterSnapshot.AngularVelocity then
			result.AngularVelocity = beforeSnapshot.AngularVelocity:Lerp(afterSnapshot.AngularVelocity, alpha)
		end
	end
	-- "Sampled" mode: keep the velocity from the nearer snapshot
	if velMode == "Sampled" then
		if alpha < 0.5 then
			result.Velocity = beforeSnapshot.Velocity
			result.AngularVelocity = beforeSnapshot.AngularVelocity
		else
			result.Velocity = afterSnapshot.Velocity
			result.AngularVelocity = afterSnapshot.AngularVelocity
		end
	end

	return result
end

--- Linear interpolation of transform positions with configurable rotation.
--- @param a CFrame
--- @param b CFrame
--- @param alpha number
--- @param rotMode string
--- @return CFrame
function Interpolation.lerpTransform(a, b, alpha, rotMode)
	local posA = a.Position
	local posB = b.Position
	local pos = posA:Lerp(posB, alpha)

	local rot
	if rotMode == "SLERP" then
		rot = Utils.slerp(a, b, alpha)
		-- Extract rotation only from slerp result
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = rot:GetComponents()
		rot = CFrame.new(0, 0, 0, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	elseif rotMode == "Linear" then
		-- Component-wise linear interpolation of rotation matrix
		local _, _, _, a00, a01, a02, a10, a11, a12, a20, a21, a22 = a:GetComponents()
		local _, _, _, b00, b01, b02, b10, b11, b12, b20, b21, b22 = b:GetComponents()
		rot = CFrame.new(
			0,
			0,
			0,
			Utils.lerp(a00, b00, alpha),
			Utils.lerp(a01, b01, alpha),
			Utils.lerp(a02, b02, alpha),
			Utils.lerp(a10, b10, alpha),
			Utils.lerp(a11, b11, alpha),
			Utils.lerp(a12, b12, alpha),
			Utils.lerp(a20, b20, alpha),
			Utils.lerp(a21, b21, alpha),
			Utils.lerp(a22, b22, alpha)
		)
	else
		-- Nearest
		if alpha < 0.5 then
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = a:GetComponents()
			rot = CFrame.new(0, 0, 0, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		else
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = b:GetComponents()
			rot = CFrame.new(0, 0, 0, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		end
	end

	return CFrame.new(pos.X, pos.Y, pos.Z) * rot
end

--- Reconstructs a State from a snapshot.
--- @param snapshot table
--- @return table State
function Interpolation.snapshotToState(snapshot)
	if not snapshot then
		return nil
	end

	return Immutable.copyAndFreeze({
		Time = snapshot.Time,
		Transform = {
			CFrame = snapshot.Transform,
			Position = snapshot.Transform.Position,
			Rotation = CFrame.fromMatrix(Vector3.new(), snapshot.Transform.RightVector, snapshot.Transform.UpVector),
		},
		Motion = {
			Velocity = snapshot.Velocity,
			AngularVelocity = snapshot.AngularVelocity,
		},
		Metadata = snapshot.Metadata or {},
		Collision = snapshot.Collision,
	})
end

return Interpolation
