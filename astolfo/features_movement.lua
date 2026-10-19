-- features_movement — Speed, Velocity, NoSlow, Bhop, TargetStrafe
local S = getgenv().Astolfo
local UserInputService = S.UserInputService

-- Speed: the sim reads moveSpeed through the module table each tick; ghosts tick
-- with zero input so only the local player is affected.
if S.physics and S.physics.Movement and type(S.physics.Movement.moveSpeed) == "function"
	and S.physics.Movement.movementSpeedAttribute and S.physics.MathHelper then
	S.orig.moveSpeed = S.physics.Movement.moveSpeed
	local f32 = S.physics.MathHelper.f32
	S.physics.Movement.moveSpeed = function(state)
		local v = f32(S.physics.Movement.movementSpeedAttribute(
			state.sprinting, state.speedLevel, state.slownessLevel, state.abilitySpeed))
		if not S.killed and S.FEATURES.speed and v then
			return v * S.VALUES.speed
		end
		return v
	end
	S.hookStatus.moveSpeed = true
end

-- Velocity: incoming knockback is applied via KbDelay.take on the client —
-- scale it there.
if S.kbDelay and type(S.kbDelay.take) == "function" then
	S.orig.take = S.kbDelay.take
	S.kbDelay.take = function(attr, tick)
		local r = S.orig.take(attr, tick)
		if not S.killed and S.FEATURES.velocity and r then
			local keep = S.VALUES.kbKeep / 100
			r.kx = (r.kx or 0) * keep
			r.ky = (r.ky or 0) * keep
			r.kz = (r.kz or 0) * keep
		end
		return r
	end
	S.hookStatus.kbTake = true
end

-- NoSlow: compensate the sneak/use input scales inside Movement.tick.
if S.physics and S.physics.Movement and type(S.physics.Movement.tick) == "function" and S.physics.Constants then
	S.orig.tick = S.physics.Movement.tick
	local SNEAK = S.physics.Constants.SNEAK_INPUT_SCALE or 0.3
	local USE = S.physics.Constants.USE_ITEM_INPUT_SCALE or 0.2
	S.physics.Movement.tick = function(state, input, world, p4)
		if not S.killed and S.FEATURES.noslow and input then
			local fwd, strafe = input.forward, input.strafe
			if state.sneaking then
				fwd, strafe = fwd / SNEAK, strafe / SNEAK
			end
			if state.usingItem then
				fwd, strafe = fwd / USE, strafe / USE
			end
			if fwd ~= input.forward or strafe ~= input.strafe then
				input = { forward = fwd, strafe = strafe, jump = input.jump }
			end
		end
		return S.orig.tick(state, input, world, p4)
	end
	S.hookStatus.tick = true
end

-- Bhop + TargetStrafe: rewrite the held input. The sim sets the local state's
-- yaw from the Look stream every tick, so while the aura aims, Forward walks
-- toward the target and strafe orbits around it.
if S.inputs and type(S.inputs.fireHeld) == "function" then
	S.orig.fireHeld = S.inputs.fireHeld
	S.inputs.fireHeld = function(handles, held)
		if not S.killed and held and UserInputService:GetFocusedTextBox() == nil then
			local strafing = S.FEATURES.strafe and S.FEATURES.aura and S.targetPos ~= nil
			if strafing then
				held.Forward = (S.targetDist or 0) > S.VALUES.attackDist * S.SPB * 1.2
				held.Back = false
				held.Left = true
				held.Right = false
			end
			if S.FEATURES.bhop then
				local moving = strafing
					or UserInputService:IsKeyDown(Enum.KeyCode.W)
					or UserInputService:IsKeyDown(Enum.KeyCode.A)
					or UserInputService:IsKeyDown(Enum.KeyCode.S)
					or UserInputService:IsKeyDown(Enum.KeyCode.D)
				if moving then
					held.Jump = true
				end
			end
		end
		return S.orig.fireHeld(handles, held)
	end
	S.hookStatus.fireHeld = true
end
