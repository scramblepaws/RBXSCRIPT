-- features_combat — KillAura: silent aim through the Look stream + client raycast
-- The game's own loop fires fireLook(handles, realYaw, realPitch) each frame and
-- the server resolves hits from those values — the camera is drawn from a
-- separate client-side look state, so rewriting this stream is invisible.
-- Instant = snap to the target every frame (classic silent rotation);
-- Smooth = bounded turn (~700 deg/s, stays under the 35 deg/tick snap budget).
local S = getgenv().Astolfo

local AIM_MAX_DEG_PER_FRAME = 11 -- ~700 deg/s at 60fps

-- FOV filter: only aim when the target is within FOV degrees of the real look
local function withinFov(realYaw, realPitch, dyaw, dpitch)
	if S.VALUES.fov >= 360 then
		return true
	end
	local dY = math.abs(((dyaw - realYaw + 180) % 360) - 180)
	local dP = math.abs(dpitch - realPitch)
	return math.sqrt(dY * dY + dP * dP) <= S.VALUES.fov
end

if S.inputs and type(S.inputs.fireLook) == "function" and S.aimAssist then
	S.orig.fireLook = S.inputs.fireLook
	S.inputs.fireLook = function(handles, yaw, pitch)
		if not S.killed and S.FEATURES.aura and (S.aimPoint or S.targetPos) then
			local ex = S.player:GetAttribute("X")
			local ey = S.player:GetAttribute("Y")
			local ez = S.player:GetAttribute("Z")
			if ex then
				local tp, ty
				if S.aimPoint then
					tp, ty = S.aimPoint, S.aimPoint.Y
				else
					tp, ty = S.targetPos, S.targetPos.Y - 0.75 * S.SPB
				end
				local exs = Vector3.new(ex, ey + 1.62, ez) * S.SPB + S.mapOrigin
				local dyaw, dpitch = S.aimAssist.anglesTo(exs.X, exs.Y, exs.Z, tp.X, ty, tp.Z)
				if not withinFov(yaw, pitch, dyaw, dpitch) then
					return S.orig.fireLook(handles, yaw, pitch)
				end
				if S.VALUES.aimMode == "Smooth" then
					local dY = ((dyaw - yaw + 180) % 360) - 180
					local dP = math.clamp(dpitch - pitch, -AIM_MAX_DEG_PER_FRAME, AIM_MAX_DEG_PER_FRAME)
					yaw = yaw + math.clamp(dY, -AIM_MAX_DEG_PER_FRAME, AIM_MAX_DEG_PER_FRAME)
					pitch = pitch + dP
				else
					yaw, pitch = dyaw, dpitch
				end
			end
		end
		return S.orig.fireLook(handles, yaw, pitch)
	end
	S.hookStatus.fireLook = true
end

if S.physics and S.physics.Combat and type(S.physics.Combat.rayHit) == "function" and S.aimAssist then
	S.orig.rayHit = S.physics.Combat.rayHit
	S.physics.Combat.rayHit = function(x, y, z, yaw, pitch, box, reach)
		-- x/y/z and box are in BLOCK units; convert the target point to blocks
		if not S.killed and S.FEATURES.aura and (S.aimPoint or S.targetPos) and box then
			local cx = (box.minX + box.maxX) / 2
			local cy = (box.minY + box.maxY) / 2
			local cz = (box.minZ + box.maxZ) / 2
			local tb = ((S.aimPoint or S.targetPos) - S.mapOrigin) / S.SPB
			if not S.aimPoint then
				tb = tb - Vector3.new(0, 0.75, 0)
			end
			local off = Vector3.new(cx - tb.X, cy - tb.Y, cz - tb.Z).Magnitude
			if off < 1.2 then
				yaw, pitch = S.aimAssist.anglesTo(x, y, z, cx, cy, cz)
			end
		end
		return S.orig.rayHit(x, y, z, yaw, pitch, box, reach)
	end
	S.hookStatus.rayHit = true
end
