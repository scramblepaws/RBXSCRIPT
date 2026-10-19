-- main — frame loop, keybinds, kill switch, init
local S = getgenv().Astolfo
local RunService = S.RunService
local UserInputService = S.UserInputService
local Workspace = S.Workspace

local RENDER_NAME = "AstolfoClient"
local connections = {}

local function step(dt)
	local camera = Workspace.CurrentCamera
	S.target, S.targetDist, S.targetPos = S.findTarget()

	-- aim at the game's own lag-compensated box nearest the target (the server
	-- raycasts these rewind boxes, not the rendered model)
	S.aimPoint = nil
	if S.FEATURES.aura and S.targetPos and S.simulation then
		local ok, list = pcall(function()
			return S.simulation.targets(2)
		end)
		if ok and typeof(list) == "table" then
			local best, bestD
			for _, e in ipairs(list) do
				local b = e.box
				if b then
					local c = Vector3.new((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2, (b.minZ + b.maxZ) / 2)
						* S.SPB + S.mapOrigin
					local d = (c - S.targetPos).Magnitude
					if d < (bestD or 8) then
						best, bestD = c, d
					end
				end
			end
			S.aimPoint = best
		end
	end

	S.stepWatermark(dt)
	S.stepGlow()
	S.updateModuleHud(dt)
	S.updateTargetHud(dt)
	S.stepEsp(dt)

	-- swing only when the victim can actually take damage (HurtRes window = 1s)
	local hurtRes = S.target and S.targetAttr(S.target, "HurtRes") or nil
	if S.FEATURES.aura and S.targetPos and camera
		and (S.targetDist or math.huge) <= S.VALUES.attackDist * S.SPB
		and (hurtRes == nil or hurtRes <= 0)
		and tick() - S.lastClick >= 1 / S.VALUES.cps then
		S.lastClick = tick()
		S.click(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	elseif S.FEATURES.autoclick and not S.FEATURES.aura and camera
		and tick() - S.lastClick >= 1 / S.VALUES.cps then
		S.lastClick = tick()
		S.click(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	end
end

if RunService.BindToRenderStep then
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value - 1, step)
else
	connections[#connections + 1] = RunService.RenderStepped:Connect(step)
end

S.connections = connections

--------------------------------------------------------------------
-- Kill switch
--------------------------------------------------------------------

function S.unload()
	if S.killed then
		return
	end
	S.killed = true
	pcall(function()
		if RunService.UnbindFromRenderStep then
			RunService:UnbindFromRenderStep(RENDER_NAME)
		end
	end)
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
	for _, d in ipairs(S.drawings) do
		pcall(function()
			d.Visible = false
			d:Remove()
		end)
	end
	table.clear(S.drawings)
	if S.glow then
		S.glow:Destroy()
		S.glow = nil
	end
	if S.guiRoot then
		S.guiRoot:Destroy()
	end
	pcall(function()
		if S.Rayfield then
			S.Rayfield:Destroy()
		end
	end)
	-- restore hooked functions
	if S.inputs then
		if S.orig.fireLook then S.inputs.fireLook = S.orig.fireLook end
		if S.orig.fireHeld then S.inputs.fireHeld = S.orig.fireHeld end
	end
	if S.kbDelay and S.orig.take then
		S.kbDelay.take = S.orig.take
	end
	local p = S.requireShared("MCPhysics")
	if p then
		if S.orig.rayHit and p.Combat then p.Combat.rayHit = S.orig.rayHit end
		if S.orig.moveSpeed and p.Movement then p.Movement.moveSpeed = S.orig.moveSpeed end
		if S.orig.tick and p.Movement then p.Movement.tick = S.orig.tick end
		if S.orig.collisionMove and p.Collision then p.Collision.move = S.orig.collisionMove end
	end
	S.restorePatches()
	pcall(function()
		if S.Luna then
			S.Luna:Destroy()
		end
	end)
	if getgenv then
		getgenv().Astolfo = nil
	end
	print("[Astolfo] unloaded — all hooks and patches restored.")
end

--------------------------------------------------------------------
-- Bind handling
--------------------------------------------------------------------

connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if S.killed then
		return
	end
	if S.capturingBind then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			S.capturingBind.set(input.KeyCode)
			S.capturingBind.button.Text = input.KeyCode.Name
			S.capturingBind = nil
		end
		return
	end
	if gameProcessed then
		return
	end
	if input.KeyCode == S.BINDS.aura then
		S.FEATURES.aura = not S.FEATURES.aura
		print("[Astolfo] KillAura " .. (S.FEATURES.aura and "ON" or "OFF")
			.. (S.target and (" — target " .. S.target.Name .. " @ " .. math.floor(S.targetDist or 0)) or " — no target in range"))
	elseif input.KeyCode == S.BINDS.speed then
		S.FEATURES.speed = not S.FEATURES.speed
		print("[Astolfo] Speed " .. (S.FEATURES.speed and ("ON x" .. S.VALUES.speed) or "OFF"))
	elseif input.KeyCode == S.BINDS.kill then
		S.unload()
	end
end)

--------------------------------------------------------------------
-- Init
--------------------------------------------------------------------

function S.start()
	S.buildGui()
	task.spawn(function()
		task.wait(1)
		print("[Astolfo][check] hooks: fireLook=" .. tostring(S.hookStatus.fireLook)
			.. " rayHit=" .. tostring(S.hookStatus.rayHit)
			.. " moveSpeed=" .. tostring(S.hookStatus.moveSpeed)
			.. " kbTake=" .. tostring(S.hookStatus.kbTake)
			.. " tick=" .. tostring(S.hookStatus.tick)
			.. " fireHeld=" .. tostring(S.hookStatus.fireHeld))
		print("[Astolfo][check] patches: " .. tostring(S.patchResult))
		print("[Astolfo] Ready — F KillAura | G Speed | L unload | RightShift GUI")
	end)
end
