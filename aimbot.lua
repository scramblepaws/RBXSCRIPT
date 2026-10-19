-- AimBot v4 — silent aim via hookfunction on the game's own hit raycast.
-- From the decompiled source:
--   * the client raycasts attacks with Combat.rayHit(eyeX, eyeY, eyeZ, yaw, pitch, box, reach),
--     testing each candidate's box; the game's own AimAssist.anglesTo gives the exact aim math.
--   * Movement.tick reads Movement.moveSpeed(state) through the module table every tick; ghosts
--     tick with zero input, so hooking moveSpeed accelerates only the local player.
-- F = toggle silent aim + auto click. G = speed. L = kill switch.

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------

local CONFIG = {
	BIND = Enum.KeyCode.F,
	KILL_BIND = Enum.KeyCode.L,
	SPEED_BIND = Enum.KeyCode.G,
	RANGE = 60, -- studs (from your camera)
	INCLUDE_BOTS = true,
	AUTO_CLICK = true,
	CLICK_INTERVAL = 0.25,
	CLICK_MAX_DIST = 6.5, -- only swing when the target is within hit range
	PATCH_REACH = true,
	REACH_COMBAT = 4.5, -- game default 3
	REACH_BLOCKS = 8, -- game default 4.5
	PATCH_ANTICHEAT = true,
	SPEED_MULT = 2.5, -- G: multiplier on the sim's own moveSpeed
	WATERMARK = "Astolfo",
	WATERMARK_ON = true,
	WATERMARK_SIZE = 40,
	WATERMARK_SPEED = 140,
	WATERMARK_BRIGHT = Color3.fromRGB(40, 170, 255),
	WATERMARK_DARK = Color3.fromRGB(6, 30, 90),
	BOX_COLOR = Color3.fromRGB(255, 60, 60),
	BOX_THICKNESS = 2,
}

--------------------------------------------------------------------
-- Services
--------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
if not player then
	warn("[Aim] Needs to run as a client local script.")
	return
end

--------------------------------------------------------------------
-- Click
--------------------------------------------------------------------

local function click(x, y)
	if type(mouse1click) == "function" then
		pcall(mouse1click)
		return true
	end
	if type(mouse1press) == "function" and type(mouse1release) == "function" then
		pcall(mouse1press)
		task.wait(0.03)
		pcall(mouse1release)
		return true
	end
	local ok = pcall(function()
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
	end)
	return ok
end

--------------------------------------------------------------------
-- Targets (avatars live in Workspace.MCPlayers and/or as Workspace children)
--------------------------------------------------------------------

local function findHead(model)
	if not model then
		return nil
	end
	local named = model:FindFirstChild("Head")
	if named and named:IsA("BasePart") then
		return named
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name:find("Head") then
			return p
		end
	end
	return nil
end

local function isTargetBody(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("Model") then
		return false
	end
	local name = inst.Name
	if name == "MCBody" then
		return false -- unpositioned template rig
	end
	if name == "MCBody " .. tostring(player.UserId) then
		return false
	end
	if name:sub(1, 6) ~= "MCBody" then
		return false
	end
	if not CONFIG.INCLUDE_BOTS and name:find("Bot") then
		return false
	end
	return true
end

local function targetCandidates()
	local seen, out = {}, {}
	local function add(container)
		if not container then
			return
		end
		for _, m in ipairs(container:GetChildren()) do
			if isTargetBody(m) and not seen[m] then
				seen[m] = true
				out[#out + 1] = m
			end
		end
	end
	add(Workspace:FindFirstChild("MCPlayers"))
	add(Workspace)
	return out
end

local function findTarget()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local best, bestDist, bestPos
	for _, m in ipairs(targetCandidates()) do
		local h = findHead(m)
		if h and h.Parent then
			local d = (h.Position - camPos).Magnitude
			if d <= CONFIG.RANGE and d < (bestDist or math.huge) then
				best, bestDist, bestPos = m, d, h.Position
			end
		end
	end
	return best, bestDist, bestPos
end

--------------------------------------------------------------------
-- Game patches
--------------------------------------------------------------------

local patches = {}

local function requireShared(name)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local mod = shared and shared:FindFirstChild(name)
	if not mod then
		return nil
	end
	local ok, res = pcall(require, mod)
	return ok and typeof(res) == "table" and res or nil
end

local function patchGame()
	local physics = requireShared("MCPhysics")
	local changed = {}
	if physics then
		if physics.Combat and physics.Combat.REACH then
			patches.reach = physics.Combat.REACH
			physics.Combat.REACH = CONFIG.REACH_COMBAT
			changed[#changed + 1] = "Combat.REACH " .. patches.reach .. "->" .. CONFIG.REACH_COMBAT
		end
		if physics.Blocks and physics.Blocks.REACH then
			patches.blockReach = physics.Blocks.REACH
			physics.Blocks.REACH = CONFIG.REACH_BLOCKS
			changed[#changed + 1] = "Blocks.REACH " .. patches.blockReach .. "->" .. CONFIG.REACH_BLOCKS
		end
	end
	if CONFIG.PATCH_ANTICHEAT then
		local config = requireShared("Config")
		if config and config.AntiCheat then
			patches.acEnabled = config.AntiCheat.Enabled
			config.AntiCheat.Enabled = false
			changed[#changed + 1] = "AntiCheat.Enabled " .. tostring(patches.acEnabled) .. "->false"
		end
	end
	return #changed > 0 and table.concat(changed, ", ") or "nothing patched"
end

local patchResult = patchGame()

local function restorePatches()
	local physics = requireShared("MCPhysics")
	if physics then
		if patches.reach and physics.Combat then
			physics.Combat.REACH = patches.reach
		end
		if patches.blockReach and physics.Blocks then
			physics.Blocks.REACH = patches.blockReach
		end
	end
	if patches.acEnabled ~= nil then
		local config = requireShared("Config")
		if config and config.AntiCheat then
			config.AntiCheat.Enabled = patches.acEnabled
		end
	end
end

--------------------------------------------------------------------
-- Hooks (the actual cheats)
-- Plain table assignment, NOT hookfunction: the game reads these through the
-- module table at call time (u7.moveSpeed(...), Combat.rayHit(...) in source),
-- so replacing the field is enough and cannot recurse.
--------------------------------------------------------------------

local enabled = false
local speedOn = false
local killed = false
local target, targetDist, targetPos
local lastClick = 0

local physics = requireShared("MCPhysics")
local aimAssist = requireShared("AimAssist")

local origRayHit, origMoveSpeed
local rayHooked = false
if physics and physics.Combat and type(physics.Combat.rayHit) == "function" and aimAssist then
	origRayHit = physics.Combat.rayHit
	physics.Combat.rayHit = function(x, y, z, yaw, pitch, box, reach)
		if enabled and not killed and targetPos and box then
			local cx = (box.minX + box.maxX) / 2
			local cy = (box.minY + box.maxY) / 2
			local cz = (box.minZ + box.maxZ) / 2
			local off = Vector3.new(cx - targetPos.X, cy - targetPos.Y, cz - targetPos.Z).Magnitude
			if off < 1.8 then -- this candidate box is our target: re-aim the ray
				yaw, pitch = aimAssist.anglesTo(x, y, z, cx, cy, cz)
			end
		end
		return origRayHit(x, y, z, yaw, pitch, box, reach)
	end
	rayHooked = true
end

local moveHooked = false
if physics and physics.Movement and type(physics.Movement.moveSpeed) == "function"
	and physics.Movement.movementSpeedAttribute and physics.MathHelper then
	origMoveSpeed = physics.Movement.moveSpeed
	local f32 = physics.MathHelper.f32
	physics.Movement.moveSpeed = function(state)
		-- same computation as the game's own moveSpeed, so the sim stays consistent
		local v = f32(physics.Movement.movementSpeedAttribute(
			state.sprinting, state.speedLevel, state.slownessLevel, state.abilitySpeed))
		if speedOn and not killed and v then
			return v * CONFIG.SPEED_MULT
		end
		return v
	end
	moveHooked = true
end

local function restoreHooks()
	local p = requireShared("MCPhysics")
	if p then
		if origRayHit and p.Combat then
			p.Combat.rayHit = origRayHit
		end
		if origMoveSpeed and p.Movement then
			p.Movement.moveSpeed = origMoveSpeed
		end
	end
end

--------------------------------------------------------------------
-- Drawings (box ESP + watermark)
--------------------------------------------------------------------

local RENDER_NAME = "UntitledAim"
local drawings = {}
local box, label, wm
local wmX = 0

do
	local ok = pcall(function()
		if not Drawing then
			error("no Drawing")
		end
		box = Drawing.new("Square")
		box.Thickness = CONFIG.BOX_THICKNESS
		box.Filled = false
		box.Color = CONFIG.BOX_COLOR
		box.Visible = false
		drawings[#drawings + 1] = box

		label = Drawing.new("Text")
		label.Size = 16
		label.Center = true
		label.Outline = true
		label.Color = CONFIG.BOX_COLOR
		label.Visible = false
		drawings[#drawings + 1] = label

		wm = Drawing.new("Text")
		wm.Text = CONFIG.WATERMARK
		wm.Size = CONFIG.WATERMARK_SIZE
		wm.Center = false
		wm.Outline = true
		wm.Color = CONFIG.WATERMARK_BRIGHT
		wm.Visible = CONFIG.WATERMARK_ON
		drawings[#drawings + 1] = wm
	end)
	if not ok then
		warn("[Aim] Drawing API unavailable — aiming still works, no box/watermark.")
	end
end

--------------------------------------------------------------------
-- Per-frame loop: track the target, draw ESP, auto-click
--------------------------------------------------------------------

local wmClock = 0
local function stepWatermark(dt)
	if not wm or not wm.Visible then
		return
	end
	dt = dt or 0
	wmClock = wmClock + dt
	local screenW = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X) or 1920
	local width = math.max(#wm.Text * CONFIG.WATERMARK_SIZE * 0.6, 120)
	wmX = wmX + CONFIG.WATERMARK_SPEED * dt
	if wmX > screenW then
		wmX = -width
	end
	local t = (math.sin(wmClock * 2) + 1) / 2
	wm.Position = Vector2.new(wmX, 10)
	wm.Size = CONFIG.WATERMARK_SIZE + t * 4
	wm.Color = CONFIG.WATERMARK_BRIGHT:Lerp(CONFIG.WATERMARK_DARK, t)
end

wmX = -300

local function step(dt)
	local camera = Workspace.CurrentCamera
	target, targetDist, targetPos = findTarget()

	local screenPos
	if targetPos and camera then
		local p, onScreen = camera:WorldToViewportPoint(targetPos)
		screenPos = onScreen and p or nil
	end

	stepWatermark(dt)

	if box and label then
		if screenPos then
			local dist = targetDist or 0
			local size = math.clamp(900 / math.max(dist, 1), 24, 260)
			box.Size = Vector2.new(size, size * 1.35)
			box.Position = Vector2.new(screenPos.X - size / 2, screenPos.Y - size * 0.68)
			box.Visible = true
			label.Position = Vector2.new(screenPos.X, screenPos.Y - size * 0.78 - 14)
			label.Text = target.Name .. "  [" .. math.floor(dist) .. "]"
			label.Visible = true
		else
			box.Visible = false
			label.Visible = false
		end
	end

	if enabled and CONFIG.AUTO_CLICK and targetPos and camera
		and (targetDist or math.huge) <= CONFIG.CLICK_MAX_DIST
		and tick() - lastClick >= CONFIG.CLICK_INTERVAL then
		lastClick = tick()
		click(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	end
end

local connections = {}
if RunService.BindToRenderStep then
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value - 1, step)
else
	connections[#connections + 1] = RunService.RenderStepped:Connect(step)
end

--------------------------------------------------------------------
-- Kill switch
--------------------------------------------------------------------

local function unload()
	killed = true
	enabled = false
	speedOn = false
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
	for _, d in ipairs(drawings) do
		pcall(function()
			d.Visible = false
			d:Remove()
		end)
	end
	table.clear(drawings)
	box, label, wm = nil, nil, nil
	restoreHooks()
	restorePatches()
	if getgenv then
		getgenv().Aim = nil
	end
	print("[Aim] script killed — hooks restored, patches restored, drawings removed.")
end

--------------------------------------------------------------------
-- Bind
--------------------------------------------------------------------

connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.BIND then
		enabled = not enabled
		print("[Aim] silent aim " .. (enabled and "ON" or "OFF")
			.. (target and (" — target " .. target.Name .. " @ " .. math.floor(targetDist or 0)) or " — no target in range"))
	elseif input.KeyCode == CONFIG.KILL_BIND then
		unload()
	elseif input.KeyCode == CONFIG.SPEED_BIND then
		speedOn = not speedOn
		print("[Aim] speed " .. (speedOn and ("ON (moveSpeed x" .. CONFIG.SPEED_MULT .. ")") or "OFF"))
	end
end)

--------------------------------------------------------------------
-- SELF CHECK
--------------------------------------------------------------------

if getgenv then
	getgenv().Aim = { findTarget = findTarget, click = click, candidates = targetCandidates }
end

task.spawn(function()
	task.wait(1)
	local a, b = Vector3.new(0, 0, 0), Vector3.new(1, 0, 0)
	local lv = CFrame.lookAt(a, b).LookVector
	assert((lv - (b - a).Unit).Magnitude < 1e-4, "[Aim] lookAt math broken")

	print("[Aim][check] silent aim hook: " .. tostring(rayHooked))
	print("[Aim][check] speed hook: " .. tostring(moveHooked))
	local cands = targetCandidates()
	local names = {}
	for _, m in ipairs(cands) do
		names[#names + 1] = m.Name
	end
	print("[Aim][check] targets: " .. #names .. " (" .. table.concat(names, ", ") .. ")")
	print("[Aim][check] patches: " .. tostring(patchResult))
	print("[Aim] Ready — " .. CONFIG.BIND.Name .. " silent aim | " .. CONFIG.SPEED_BIND.Name
		.. " speed | " .. CONFIG.KILL_BIND.Name .. " kill script")
end)
