-- Astolfo v5 — a small "client" for this game, modeled after Minecraft cheat
-- clients (KillAura, Velocity, Autoclicker, Speed, NoSlow, Bhop, ESP, GUI).
-- Everything hooks the game's own tables/APIs found in its source:
--   * hits are authoritative in Simulation.resolveAttack, which reads yaw/pitch
--     from the replicated Look binding (Inputs.fireLook) — so silent aim rewrites
--     that stream (rate-limited), camera untouched.
--   * incoming knockback arrives via the player's "Kb" attribute and is applied
--     through KbDelay.take — zero it there.
--   * server reach allowance = Combat.REACH (3) + ReachTolerance (0.3); stay inside.
-- F = KillAura | G = Speed | L = unload | RightShift = GUI

--------------------------------------------------------------------
-- CONFIG / state
--------------------------------------------------------------------

local FEATURES = {
	aura = false,
	velocity = false,
	noslow = false,
	bhop = false,
	speed = false,
	glow = true,
	strafe = false,
	esp = true,
	watermark = true,
}
local VALUES = {
	cps = 10, -- 1..20
	range = 60, -- studs
	reach = 3.2, -- blocks (server tolerance is 3.3 — above gets flagged)
	attackDist = 3.4, -- blocks, click only when closer than this
	speed = 2.5, -- 1..5 multiplier
	kbKeep = 0, -- 0..100: % of incoming knockback kept (0 = none)
	targets = "All", -- All / Players / Bots
	aimMode = "Instant", -- Instant (silent snap) / Smooth (rate-limited)
}
local BINDS = {
	aura = Enum.KeyCode.F,
	speed = Enum.KeyCode.G,
	kill = Enum.KeyCode.L,
	gui = Enum.KeyCode.RightShift,
}

local WATERMARK_TEXT = "astolfo"

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
	warn("[Astolfo] Needs to run as a client local script.")
	return
end

local killed = false
local target, targetDist, targetPos
local lastClick = 0

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
-- Targets
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
	if name == "MCBody" or name == "MCBody " .. tostring(player.UserId) or name:sub(1, 6) ~= "MCBody" then
		return false
	end
	if VALUES.targets == "Players" and name:find("Bot") then
		return false
	end
	if VALUES.targets == "Bots" and not name:find("Bot") then
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

-- The camera is Scriptable and unreliable in this game; the sim keeps the real
-- position in the player's own attributes — in BLOCK units. Render models are in
-- studs: studs = blocks * STUDS_PER_BLOCK + Map.Origin. Values assigned below
-- once the modules are loaded.
local SPB, mapOrigin

local function selfPos()
	local x = player:GetAttribute("X")
	local y = player:GetAttribute("Y")
	local z = player:GetAttribute("Z")
	if x then
		return Vector3.new(x, y or 0, z or 0) * SPB + mapOrigin
	end
	local camera = Workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.zero
end

local function findTarget()
	local myPos = selfPos()
	local best, bestDist, bestPos
	for _, m in ipairs(targetCandidates()) do
		local h = findHead(m)
		if h and h.Parent then
			local d = (h.Position - myPos).Magnitude
			if d <= VALUES.range and d < (bestDist or math.huge) then
				best, bestDist, bestPos = m, d, h.Position
			end
		end
	end
	return best, bestDist, bestPos
end

local function targetAttr(m, name)
	local id = m.Name:match("MCBody%s+(%S+)$")
	local mcPlayers = Workspace:FindFirstChild("MCPlayers")
	local pinst = id and mcPlayers and mcPlayers:FindFirstChild(id)
	local v = pinst and pinst:GetAttribute(name)
	if v == nil and m:FindFirstChild("Info") then
		v = m.Info:GetAttribute(name)
	end
	return v
end

local function targetHealth(m)
	return targetAttr(m, "Health")
end

-- the aim point in studs: the game's own lag-compensated box center (the server
-- raycasts these rewind boxes, not the rendered model), fallback nil
local aimPoint = nil

--------------------------------------------------------------------
-- Modules + originals (everything restored by unload)
--------------------------------------------------------------------

local function requireShared(name)
	local node = ReplicatedStorage:FindFirstChild("Shared")
	if not node then
		return nil
	end
	for part in name:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	if not node then
		return nil
	end
	local ok, res = pcall(require, node)
	return ok and typeof(res) == "table" and res or nil
end

local physics = requireShared("MCPhysics")
local aimAssist = requireShared("AimAssist")
local inputs = requireShared("Net/Inputs")
local kbDelay = requireShared("KbDelay")
local simulation = requireShared("Net/Simulation")

SPB = (physics and physics.Constants and physics.Constants.STUDS_PER_BLOCK) or 3.5714
do
	local cfg = requireShared("Config")
	if cfg and cfg.Map and cfg.Map.Origin then
		mapOrigin = cfg.Map.Origin
	else
		mapOrigin = Vector3.zero
	end
end

local orig = {} -- original functions, restored on unload

--------------------------------------------------------------------
-- Patches
--------------------------------------------------------------------

local function applyReach(v)
	if not physics or not physics.Combat then
		return
	end
	physics.Combat.REACH = v
end

local function patchGame()
	local changed = {}
	if physics then
		if physics.Combat and physics.Combat.REACH then
			orig.combatReach = physics.Combat.REACH
			applyReach(VALUES.reach)
			changed[#changed + 1] = "Combat.REACH " .. orig.combatReach .. "->" .. VALUES.reach
		end
		if physics.Blocks and physics.Blocks.REACH then
			orig.blockReach = physics.Blocks.REACH
			physics.Blocks.REACH = 4.5
			changed[#changed + 1] = "Blocks.REACH " .. orig.blockReach .. "->4.5"
		end
	end
	local config = requireShared("Config")
	if config and config.AntiCheat then
		orig.acEnabled = config.AntiCheat.Enabled
		config.AntiCheat.Enabled = false
		changed[#changed + 1] = "AntiCheat.Enabled " .. tostring(orig.acEnabled) .. "->false"
	end
	return #changed > 0 and table.concat(changed, ", ") or "nothing patched"
end

local patchResult = patchGame()

local function restorePatches()
	local p = requireShared("MCPhysics")
	if p then
		if orig.combatReach and p.Combat then
			p.Combat.REACH = orig.combatReach
		end
		if orig.blockReach and p.Blocks then
			p.Blocks.REACH = orig.blockReach
		end
	end
	if orig.acEnabled ~= nil then
		local config = requireShared("Config")
		if config and config.AntiCheat then
			config.AntiCheat.Enabled = orig.acEnabled
		end
	end
end

--------------------------------------------------------------------
-- Feature hooks (plain table replacement — the game reads fields at call time)
--------------------------------------------------------------------

local hookStatus = {}

-- KillAura part 1: silent aim through the Look stream.
-- The game's own loop fires fireLook(handles, realYaw, realPitch) each frame and
-- the server resolves hits from those values — the camera is drawn from a
-- separate client-side look state, so rewriting this stream is invisible.
-- Instant = snap to the target every frame (classic silent rotation);
-- Smooth = bounded turn (~700 deg/s, stays under the 35 deg/tick snap budget).
local AIM_MAX_DEG_PER_FRAME = 11 -- ~700 deg/s at 60fps: just under the 35 deg/tick snap budget
if inputs and type(inputs.fireLook) == "function" and aimAssist then
	orig.fireLook = inputs.fireLook
	inputs.fireLook = function(handles, yaw, pitch)
		if not killed and FEATURES.aura and (aimPoint or targetPos) then
			local ex = player:GetAttribute("X")
			local ey = player:GetAttribute("Y")
			local ez = player:GetAttribute("Z")
			if ex then
				local tp, ty
				if aimPoint then
					tp, ty = aimPoint, aimPoint.Y
				else
					tp, ty = targetPos, targetPos.Y - 0.75 * SPB
				end
				local exs = Vector3.new(ex, ey + 1.62, ez) * SPB + mapOrigin
				local dyaw, dpitch = aimAssist.anglesTo(exs.X, exs.Y, exs.Z, tp.X, ty, tp.Z)
				if VALUES.aimMode == "Smooth" then
					local dY = ((dyaw - yaw + 180) % 360) - 180
					local dP = math.clamp(dpitch - pitch, -AIM_MAX_DEG_PER_FRAME, AIM_MAX_DEG_PER_FRAME)
					yaw = yaw + math.clamp(dY, -AIM_MAX_DEG_PER_FRAME, AIM_MAX_DEG_PER_FRAME)
					pitch = pitch + dP
				else
					yaw, pitch = dyaw, dpitch
				end
			end
		end
		return orig.fireLook(handles, yaw, pitch)
	end
	hookStatus.fireLook = true
end

-- KillAura part 2: client-side prediction raycast also aims at the target
if physics and physics.Combat and type(physics.Combat.rayHit) == "function" and aimAssist then
	orig.rayHit = physics.Combat.rayHit
	physics.Combat.rayHit = function(x, y, z, yaw, pitch, box, reach)
		-- x/y/z and box are in BLOCK units; convert the target point to blocks
		if not killed and FEATURES.aura and (aimPoint or targetPos) and box then
			local cx = (box.minX + box.maxX) / 2
			local cy = (box.minY + box.maxY) / 2
			local cz = (box.minZ + box.maxZ) / 2
			local tb = ((aimPoint or targetPos) - mapOrigin) / SPB
			if not aimPoint then
				tb = tb - Vector3.new(0, 0.75, 0)
			end
			local off = Vector3.new(cx - tb.X, cy - tb.Y, cz - tb.Z).Magnitude
			if off < 1.2 then
				yaw, pitch = aimAssist.anglesTo(x, y, z, cx, cy, cz)
			end
		end
		return orig.rayHit(x, y, z, yaw, pitch, box, reach)
	end
	hookStatus.rayHit = true
end

-- Speed: the sim reads moveSpeed through the module table each tick; ghosts tick
-- with zero input so only the local player is affected.
if physics and physics.Movement and type(physics.Movement.moveSpeed) == "function"
	and physics.Movement.movementSpeedAttribute and physics.MathHelper then
	orig.moveSpeed = physics.Movement.moveSpeed
	local f32 = physics.MathHelper.f32
	physics.Movement.moveSpeed = function(state)
		local v = f32(physics.Movement.movementSpeedAttribute(
			state.sprinting, state.speedLevel, state.slownessLevel, state.abilitySpeed))
		if not killed and FEATURES.speed and v then
			return v * VALUES.speed
		end
		return v
	end
	hookStatus.moveSpeed = true
end

-- Velocity: incoming knockback is applied via KbDelay.take on the client —
-- zero it there.
if kbDelay and type(kbDelay.take) == "function" then
	orig.take = kbDelay.take
	kbDelay.take = function(attr, tick)
		local r = orig.take(attr, tick)
		if not killed and FEATURES.velocity and r then
			local keep = VALUES.kbKeep / 100
			r.kx = (r.kx or 0) * keep
			r.ky = (r.ky or 0) * keep
			r.kz = (r.kz or 0) * keep
		end
		return r
	end
	hookStatus.kbTake = true
end

-- NoSlow: compensate the sneak/use input scales inside Movement.tick.
if physics and physics.Movement and type(physics.Movement.tick) == "function" and physics.Constants then
	orig.tick = physics.Movement.tick
	local SNEAK = physics.Constants.SNEAK_INPUT_SCALE or 0.3
	local USE = physics.Constants.USE_ITEM_INPUT_SCALE or 0.2
	physics.Movement.tick = function(state, input, world, p4)
		if not killed and FEATURES.noslow and input then
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
		return orig.tick(state, input, world, p4)
	end
	hookStatus.tick = true
end

-- Bhop + TargetStrafe: rewrite the held input. The sim sets the local state's
-- yaw from the Look stream every tick, so while the aura aims, Forward walks
-- toward the target and strafe orbits around it.
if inputs and type(inputs.fireHeld) == "function" then
	orig.fireHeld = inputs.fireHeld
	inputs.fireHeld = function(handles, held)
		if not killed and held and UserInputService:GetFocusedTextBox() == nil then
			local strafing = FEATURES.strafe and FEATURES.aura and targetPos ~= nil
			if strafing then
				held.Forward = (targetDist or 0) > VALUES.attackDist * SPB * 1.2
				held.Back = false
				held.Left = true
				held.Right = false
			end
			if FEATURES.bhop then
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
		return orig.fireHeld(handles, held)
	end
	hookStatus.fireHeld = true
end

--------------------------------------------------------------------
-- Drawings: watermark + ESP box + tracers
--------------------------------------------------------------------

local RENDER_NAME = "AstolfoClient"
local drawings = {}
local label, wmPanel
local wmLetters = {}
local boxPool, tracerPool, hpBgPool, hpFgPool = {}, {}, {}, {}
local moduleTexts, hudPanel, hudName, hudHpText, hudBarBg, hudBarFill, hudDist

do
	local ok = pcall(function()
		if not Drawing then
			error("no Drawing")
		end
		label = Drawing.new("Text")
		label.Size = 16
		label.Center = true
		label.Outline = true
		label.Color = Color3.fromRGB(255, 255, 255)
		label.Visible = false
		drawings[#drawings + 1] = label

		wmPanel = Drawing.new("Square")
		wmPanel.Filled = true
		wmPanel.Color = Color3.fromRGB(10, 10, 10)
		wmPanel.Transparency = 0.5
		wmPanel.Visible = FEATURES.watermark
		drawings[#drawings + 1] = wmPanel

		-- "astolfo" letter by letter so the pink->lavender wave can flow across it
		for i = 1, #WATERMARK_TEXT do
			local d = Drawing.new("Text")
			d.Text = WATERMARK_TEXT:sub(i, i)
			d.Size = 26
			d.Outline = true
			d.Color = Color3.fromRGB(255, 158, 208)
			d.Position = Vector2.new(10 + (i - 1) * 16, 8)
			d.Visible = FEATURES.watermark
			drawings[#drawings + 1] = d
			wmLetters[#wmLetters + 1] = d
		end

		for _ = 1, 24 do
			local sq = Drawing.new("Square")
			sq.Thickness = 2
			sq.Filled = false
			sq.Color = Color3.fromRGB(255, 60, 60)
			sq.Visible = false
			drawings[#drawings + 1] = sq
			boxPool[#boxPool + 1] = sq

			local tr = Drawing.new("Line")
			tr.Thickness = 1
			tr.Color = Color3.fromRGB(255, 90, 90)
			tr.Transparency = 0.45
			tr.Visible = false
			drawings[#drawings + 1] = tr
			tracerPool[#tracerPool + 1] = tr

			local hbg = Drawing.new("Square")
			hbg.Filled = true
			hbg.Color = Color3.fromRGB(10, 10, 10)
			hbg.Transparency = 0.4
			hbg.Visible = false
			drawings[#drawings + 1] = hbg
			hpBgPool[#hpBgPool + 1] = hbg

			local hfg = Drawing.new("Square")
			hfg.Filled = true
			hfg.Color = Color3.fromRGB(80, 255, 100)
			hfg.Visible = false
			drawings[#drawings + 1] = hfg
			hpFgPool[#hpFgPool + 1] = hfg
		end

		-- active module list (gradient cycling pink <-> lavender)
		moduleTexts = {}
		for _ = 1, 12 do
			local d = Drawing.new("Text")
			d.Size = 15
			d.Outline = true
			d.Visible = false
			drawings[#drawings + 1] = d
			moduleTexts[#moduleTexts + 1] = d
		end

		-- TargetHUD (bottom-left panel: name, smooth health bar, distance)
		hudPanel = Drawing.new("Square")
		hudPanel.Filled = true
		hudPanel.Color = Color3.fromRGB(8, 8, 12)
		hudPanel.Transparency = 0.4
		hudPanel.Visible = false
		drawings[#drawings + 1] = hudPanel

		hudName = Drawing.new("Text")
		hudName.Size = 15
		hudName.Outline = true
		hudName.Color = Color3.fromRGB(240, 240, 245)
		hudName.Visible = false
		drawings[#drawings + 1] = hudName

		hudDist = Drawing.new("Text")
		hudDist.Size = 12
		hudDist.Center = true
		hudDist.Outline = true
		hudDist.Color = Color3.fromRGB(255, 158, 208)
		hudDist.Visible = false
		drawings[#drawings + 1] = hudDist

		hudBarBg = Drawing.new("Square")
		hudBarBg.Filled = true
		hudBarBg.Color = Color3.fromRGB(30, 30, 40)
		hudBarBg.Visible = false
		drawings[#drawings + 1] = hudBarBg

		hudBarFill = Drawing.new("Square")
		hudBarFill.Filled = true
		hudBarFill.Color = Color3.fromRGB(255, 158, 208)
		hudBarFill.Visible = false
		drawings[#drawings + 1] = hudBarFill

		hudHpText = Drawing.new("Text")
		hudHpText.Size = 12
		hudHpText.Outline = true
		hudHpText.Color = Color3.fromRGB(220, 220, 230)
		hudHpText.Visible = false
		drawings[#drawings + 1] = hudHpText
	end)
	if not ok then
		warn("[Astolfo] Drawing API unavailable — no ESP/watermark.")
	end
end

local wmClock = 0
local function setWmVisible(v)
	if wmPanel then
		wmPanel.Visible = v
	end
	for _, d in ipairs(wmLetters) do
		d.Visible = v
	end
end

-- chroma wave: pink -> lavender flows left to right across the letters
local function stepWatermark(dt)
	dt = dt or 0
	wmClock = wmClock + dt
	for i, d in ipairs(wmLetters) do
		if d.Visible then
			local u = (wmClock * 0.35 - i * 0.13) % 1
			d.Color = Color3.fromRGB(255, 158, 208):Lerp(Color3.fromRGB(180, 155, 255), u)
		end
	end
end

-- bright glow around the KillAura target (visible through walls)
local glow = nil
local function stepGlow()
	local show = not killed and FEATURES.aura and FEATURES.glow and target
	if show then
		if not glow then
			glow = Instance.new("Highlight")
			glow.Name = "AstolfoTarget"
			glow.FillColor = Color3.fromRGB(255, 45, 45)
			glow.FillTransparency = 0.55
			glow.OutlineColor = Color3.fromRGB(255, 70, 70)
			glow.OutlineTransparency = 0
			glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		end
		if glow.Parent ~= target then
			glow.Parent = target
		end
	elseif glow then
		glow.Parent = nil
	end
end

-- active module list: gradient cycling pink <-> lavender, Astolfo-style
local MODULE_HUD_ORDER = {
	{ name = "KillAura", get = function() return FEATURES.aura end },
	{ name = "Velocity", get = function() return FEATURES.velocity end },
	{ name = "Speed", get = function() return FEATURES.speed end },
	{ name = "TargetStrafe", get = function() return FEATURES.strafe end },
	{ name = "Bhop", get = function() return FEATURES.bhop end },
	{ name = "NoSlow", get = function() return FEATURES.noslow end },
	{ name = "ESP", get = function() return FEATURES.esp end },
}

local function updateModuleHud(dt)
	if not moduleTexts or #moduleTexts == 0 then
		return
	end
	local active = {}
	for _, e in ipairs(MODULE_HUD_ORDER) do
		if e.get() then
			active[#active + 1] = e.name
		end
	end
	-- black backdrop behind the watermark + list
	if wmPanel then
		local on = FEATURES.watermark or #active > 0
		wmPanel.Visible = on
		wmPanel.Size = Vector2.new(168, 30 + #active * 18)
		wmPanel.Position = Vector2.new(4, 4)
	end
	for i = 1, #moduleTexts do
		local d = moduleTexts[i]
		if i <= #active then
			d.Text = active[i]
			-- same chroma wave as the logo, flowing down the list
			local u = (wmClock * 0.35 - (i + 2) * 0.13) % 1
			d.Color = Color3.fromRGB(255, 158, 208):Lerp(Color3.fromRGB(180, 155, 255), u)
			d.Position = Vector2.new(10, 38 + (i - 1) * 18)
			d.Size = 14
			d.Visible = true
		else
			d.Visible = false
		end
	end
end

-- TargetHUD: name, smooth health bar with damage flash, distance
local hudHpShown = 20
local hudFlash = 0
local function updateTargetHud(dt)
	local show = not killed and FEATURES.aura and target
	if not (hudPanel and hudName) then
		return
	end
	if not show then
		hudPanel.Visible = false
		hudName.Visible = false
		hudDist.Visible = false
		hudBarBg.Visible = false
		hudBarFill.Visible = false
		hudHpText.Visible = false
		return
	end
	local hp = targetAttr(target, "Health")
	if hp then
		if hp < hudHpShown - 0.01 then
			hudFlash = 0.3
		end
		hudHpShown = hudHpShown + (hp - hudHpShown) * math.min(1, dt * 8)
	else
		hudHpShown = 20
	end
	hudFlash = math.max(0, hudFlash - dt)
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	local px, py = 10, vp.Y - 110
	hudPanel.Size = Vector2.new(230, 84)
	hudPanel.Position = Vector2.new(px, py)
	hudPanel.Visible = true
	hudName.Position = Vector2.new(px + 14, py + 10)
	hudName.Text = target.Name
	hudName.Visible = true
	hudDist.Position = Vector2.new(px + 214, py + 14)
	hudDist.Text = math.floor(targetDist or 0) .. "m"
	hudDist.Visible = true
	hudBarBg.Size = Vector2.new(200, 10)
	hudBarBg.Position = Vector2.new(px + 14, py + 42)
	hudBarBg.Visible = true
	hudBarFill.Size = Vector2.new(math.max(0, 200 * math.clamp(hudHpShown / 20, 0, 1)), 10)
	hudBarFill.Position = Vector2.new(px + 14, py + 42)
	hudBarFill.Color = hudFlash > 0 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 158, 208)
	hudBarFill.Visible = true
	hudHpText.Position = Vector2.new(px + 14, py + 58)
	hudHpText.Text = string.format("%.1f / 20", hudHpShown)
	hudHpText.Visible = true
end

local function step(dt)
	local camera = Workspace.CurrentCamera
	target, targetDist, targetPos = findTarget()

	-- aim at the game's own lag-compensated box nearest the target (the server
	-- raycasts these rewind boxes, not the rendered model)
	aimPoint = nil
	if FEATURES.aura and targetPos and simulation then
		local ok, list = pcall(function()
			return simulation.targets(2)
		end)
		if ok and typeof(list) == "table" then
			local best, bestD
			for _, e in ipairs(list) do
				local b = e.box
				if b then
					local c = Vector3.new((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2, (b.minZ + b.maxZ) / 2)
						* SPB + mapOrigin
					local d = (c - targetPos).Magnitude
					if d < (bestD or 8) then
						best, bestD = c, d
					end
				end
			end
			aimPoint = best
		end
	end

	stepWatermark(dt)
	stepGlow()
	updateModuleHud(dt)
	updateTargetHud(dt)

	local screenPos
	if targetPos and camera then
		local p, onScreen = camera:WorldToViewportPoint(targetPos)
		screenPos = onScreen and p or nil
	end

	-- ESP: 2D box + health bar + tracer to bottom-center for everyone in range
	if FEATURES.esp and camera then
		local myPos = selfPos()
		local cands = targetCandidates()
		local vp = camera.ViewportSize
		for i = 1, #boxPool do
			local m = cands[i]
			local sq, tr, hbg, hfg = boxPool[i], tracerPool[i], hpBgPool[i], hpFgPool[i]
			if m then
				local h = findHead(m)
				if h and h.Parent then
					local p, onScreen = camera:WorldToViewportPoint(h.Position)
					if onScreen then
						local d = (h.Position - myPos).Magnitude
						local size = math.clamp(900 / math.max(d, 1), 18, 180)
						sq.Size = Vector2.new(size, size * 1.35)
						sq.Position = Vector2.new(p.X - size / 2, p.Y - size * 0.68)
						sq.Thickness = m == target and 3 or 2
						sq.Color = m == target and Color3.fromRGB(255, 255, 120) or Color3.fromRGB(255, 60, 60)
						sq.Visible = true
						tr.From = Vector2.new(p.X, p.Y)
						tr.To = Vector2.new(vp.X / 2, vp.Y)
						tr.Visible = true
						local hp = targetHealth(m)
						if hp then
							local frac = math.clamp(hp / 20, 0, 1)
							hbg.Position = Vector2.new(p.X - size / 2, p.Y - size * 0.68 - 7)
							hbg.Size = Vector2.new(size, 5)
							hbg.Visible = true
							hfg.Position = hbg.Position
							hfg.Size = Vector2.new(size * frac, 5)
							hfg.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 90), frac)
							hfg.Visible = true
						else
							hbg.Visible = false
							hfg.Visible = false
						end
					else
						sq.Visible, tr.Visible, hbg.Visible, hfg.Visible = false, false, false, false
					end
				else
					sq.Visible, tr.Visible, hbg.Visible, hfg.Visible = false, false, false, false
				end
			else
				sq.Visible, tr.Visible, hbg.Visible, hfg.Visible = false, false, false, false
			end
		end
		if label then
			if screenPos and target then
				local hp = targetHealth(target)
				label.Position = Vector2.new(screenPos.X, screenPos.Y - 60)
				label.Text = target.Name .. " [" .. math.floor(targetDist or 0) .. "]"
					.. (hp and ("  " .. math.floor(hp) .. "hp") or "")
				label.Visible = true
			else
				label.Visible = false
			end
		end
	elseif boxPool[1] then
		for i = 1, #boxPool do
			boxPool[i].Visible = false
			tracerPool[i].Visible = false
			hpBgPool[i].Visible = false
			hpFgPool[i].Visible = false
		end
		if label then
			label.Visible = false
		end
	end

	-- swing only when the victim can actually take damage (HurtRes window = 1s)
	local hurtRes = target and targetAttr(target, "HurtRes") or nil
	if FEATURES.aura and targetPos and camera
		and (targetDist or math.huge) <= VALUES.attackDist * SPB
		and (hurtRes == nil or hurtRes <= 0)
		and tick() - lastClick >= 1 / VALUES.cps then
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
-- GUI
--------------------------------------------------------------------

local ACCENT = Color3.fromRGB(255, 158, 208) -- bubblegum pink
local ACCENT2 = Color3.fromRGB(180, 155, 255) -- lavender
local PANEL = Color3.fromRGB(11, 11, 15) -- deep black
local PANEL2 = Color3.fromRGB(22, 22, 30)
local TEXT = Color3.fromRGB(235, 235, 240)
local DIM = Color3.fromRGB(150, 140, 160)
local guiRoot, guiSidebar, guiPane
local capturingBind = nil
local guiSelected = { cat = "Combat", name = "KillAura" }

-- pill-shaped corners for the Astolfo look
local function pill(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 14)
	c.Parent = inst
end

local MODULES = {
	{ cat = "Combat", name = "KillAura", get = function() return FEATURES.aura end, set = function(v)
		FEATURES.aura = v
		print("[Astolfo] KillAura " .. (v and "ON" or "OFF"))
	end, bind = function() return BINDS.aura end, rows = {
		{ type = "slider", label = "CPS", get = function() return VALUES.cps end, set = function(v) VALUES.cps = v end, min = 1, max = 20, step = 1 },
		{ type = "slider", label = "Range", get = function() return VALUES.range end, set = function(v) VALUES.range = v end, min = 10, max = 60, step = 5 },
		{ type = "slider", label = "Reach", get = function() return VALUES.reach end, set = function(v)
			VALUES.reach = v
			applyReach(v)
		end, min = 2.5, max = 4, step = 0.1 },
		{ type = "slider", label = "AttackDist", get = function() return VALUES.attackDist end, set = function(v) VALUES.attackDist = v end, min = 2.5, max = 4.5, step = 0.1 },
		{ type = "cycle", label = "Targets", get = function() return VALUES.targets end, set = function(v) VALUES.targets = v end, options = { "All", "Players", "Bots" } },
		{ type = "cycle", label = "Aim", get = function() return VALUES.aimMode end, set = function(v) VALUES.aimMode = v end, options = { "Instant", "Smooth" } },
		{ type = "toggle", label = "Glow target", get = function() return FEATURES.glow end, set = function(v) FEATURES.glow = v end },
		{ type = "toggle", label = "TargetStrafe", get = function() return FEATURES.strafe end, set = function(v)
			FEATURES.strafe = v
			print("[Astolfo] TargetStrafe " .. (v and "ON" or "OFF"))
		end },
	} },
	{ cat = "Combat", name = "Velocity", get = function() return FEATURES.velocity end, set = function(v)
		FEATURES.velocity = v
		print("[Astolfo] Velocity " .. (v and "ON" or "OFF"))
	end, rows = {
		{ type = "slider", label = "KB keep %", get = function() return VALUES.kbKeep end, set = function(v) VALUES.kbKeep = v end, min = 0, max = 100, step = 10 },
	} },
	{ cat = "Movement", name = "Speed", get = function() return FEATURES.speed end, set = function(v)
		FEATURES.speed = v
		print("[Astolfo] Speed " .. (v and ("ON x" .. VALUES.speed) or "OFF"))
	end, bind = function() return BINDS.speed end, rows = {
		{ type = "slider", label = "Multiplier", get = function() return VALUES.speed end, set = function(v) VALUES.speed = v end, min = 1, max = 5, step = 0.5 },
	} },
	{ cat = "Movement", name = "Bhop", get = function() return FEATURES.bhop end, set = function(v) FEATURES.bhop = v end },
	{ cat = "Movement", name = "NoSlow", get = function() return FEATURES.noslow end, set = function(v) FEATURES.noslow = v end },
	{ cat = "Render", name = "ESP", get = function() return FEATURES.esp end, set = function(v) FEATURES.esp = v end },
	{ cat = "Render", name = "Watermark", get = function() return FEATURES.watermark end, set = function(v)
		FEATURES.watermark = v
		setWmVisible(v)
	end },
	{ cat = "Client", name = "Keybinds", rows = {
		{ type = "bind", label = "Aura", get = function() return BINDS.aura end, set = function(k) BINDS.aura = k end },
		{ type = "bind", label = "Speed", get = function() return BINDS.speed end, set = function(k) BINDS.speed = k end },
		{ type = "bind", label = "Kill", get = function() return BINDS.kill end, set = function(k) BINDS.kill = k end },
		{ type = "bind", label = "GUI", get = function() return BINDS.gui end, set = function(k) BINDS.gui = k end },
		{ type = "unload" },
	} },
}

local function selectedModule()
	for _, m in ipairs(MODULES) do
		if m.cat == guiSelected.cat and m.name == guiSelected.name then
			return m
		end
	end
	return MODULES[1]
end

local function clearChildren(c)
	for _, ch in ipairs(c:GetChildren()) do
		if not ch:IsA("UILayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
end

local function renderSidebar()
	clearChildren(guiSidebar)
	for _, cat in ipairs({ "Combat", "Movement", "Render", "Client" }) do
		local catBtn = Instance.new("TextButton")
		catBtn.Size = UDim2.new(1, -12, 0, 20)
		catBtn.BackgroundColor3 = cat == guiSelected.cat and PANEL2 or PANEL
		catBtn.TextColor3 = cat == guiSelected.cat and ACCENT or DIM
		catBtn.Text = cat
		catBtn.TextXAlignment = Enum.TextXAlignment.Left
		catBtn.TextSize = 12
		catBtn.Font = Enum.Font.GothamBold
		catBtn.BorderSizePixel = 0
		catBtn.AutoButtonColor = false
		pill(catBtn, 10)
		catBtn.MouseButton1Click:Connect(function()
			guiSelected.cat = cat
			local first
			for _, m in ipairs(MODULES) do
				if m.cat == cat then
					first = first or m.name
				end
			end
			guiSelected.name = first or ""
			renderSidebar()
			renderPane()
		end)
		catBtn.Parent = guiSidebar

		for _, m in ipairs(MODULES) do
			if m.cat == cat then
				local sel = guiSelected.name == m.name and guiSelected.cat == cat
				local on = m.get and m.get()
				local row = Instance.new("TextButton")
				row.Size = UDim2.new(1, -12, 0, 24)
				row.BackgroundColor3 = sel and PANEL2 or PANEL
				row.TextColor3 = (sel and ACCENT) or (on and Color3.fromRGB(150, 200, 255) or TEXT)
				row.Text = m.name
				row.TextXAlignment = Enum.TextXAlignment.Left
				row.TextSize = 13
				row.BorderSizePixel = 0
				row.AutoButtonColor = false
				pill(row, 12)
				if on then
					local g = Instance.new("UIGradient")
					g.Color = ColorSequence.new(ACCENT2, ACCENT)
					g.Parent = row
					row.BackgroundColor3 = Color3.new(1, 1, 1)
				end
				row.MouseButton1Click:Connect(function()
					guiSelected = { cat = cat, name = m.name }
					if m.set then
						m.set(not m.get())
					end
					renderSidebar()
					renderPane()
				end)
				row.Parent = guiSidebar
				if m.bind then
					local badge = Instance.new("TextLabel")
					badge.Size = UDim2.new(0, 34, 1, 0)
					badge.Position = UDim2.new(1, -34, 0, 0)
					badge.BackgroundTransparency = 1
					badge.TextColor3 = DIM
					badge.Text = "[" .. m.bind().Name .. "]"
					badge.TextXAlignment = Enum.TextXAlignment.Right
					badge.TextSize = 11
					badge.Parent = row
				end
			end
		end
	end
end

local function renderRow(spec)
	if spec.type == "toggle" then
		local b = Instance.new("TextButton")
		local function refresh()
			local on = spec.get()
			b.Text = on and "ON" or "OFF"
			if on then
				b.BackgroundColor3 = ACCENT
				b.TextColor3 = Color3.fromRGB(12, 12, 16)
			else
				b.BackgroundColor3 = PANEL2
				b.TextColor3 = DIM
			end
		end
		refresh()
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.TextSize = 13
		pill(b, 14)
		b.MouseButton1Click:Connect(function()
			spec.set(not spec.get())
			refresh()
		end)
		return b
	elseif spec.type == "slider" then
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		local minus = Instance.new("TextButton")
		minus.Size = UDim2.new(0, 26, 1, 0)
		minus.Position = UDim2.new(0, 0, 0, 0)
		minus.Text = "-"
		minus.BackgroundColor3 = PANEL2
		minus.TextColor3 = TEXT
		minus.BorderSizePixel = 0
		minus.TextSize = 13
		pill(minus, 10)
		minus.Parent = frame
		local value = Instance.new("TextButton")
		value.Size = UDim2.new(1, -56, 1, 0)
		value.Position = UDim2.new(0, 28, 0, 0)
		value.Text = tostring(spec.get())
		value.BackgroundColor3 = PANEL
		value.TextColor3 = ACCENT
		value.BorderSizePixel = 0
		value.AutoButtonColor = false
		value.TextSize = 13
		pill(value, 10)
		value.Parent = frame
		local plus = Instance.new("TextButton")
		plus.Size = UDim2.new(0, 26, 1, 0)
		plus.Position = UDim2.new(1, -26, 0, 0)
		plus.Text = "+"
		plus.BackgroundColor3 = PANEL2
		plus.TextColor3 = TEXT
		plus.BorderSizePixel = 0
		plus.TextSize = 13
		pill(plus, 10)
		plus.Parent = frame
		local function refresh()
			value.Text = tostring(spec.get())
		end
		minus.MouseButton1Click:Connect(function()
			spec.set(math.max(spec.min, spec.get() - spec.step))
			refresh()
		end)
		plus.MouseButton1Click:Connect(function()
			spec.set(math.min(spec.max, spec.get() + spec.step))
			refresh()
		end)
		return frame
	elseif spec.type == "cycle" then
		local b = Instance.new("TextButton")
		b.Text = spec.get()
		b.BackgroundColor3 = PANEL2
		b.TextColor3 = ACCENT
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.TextSize = 13
		pill(b, 14)
		b.MouseButton1Click:Connect(function()
			local i = 1
			for idx, o in ipairs(spec.options) do
				if o == spec.get() then
					i = idx
				end
			end
			i = i % #spec.options + 1
			spec.set(spec.options[i])
			b.Text = spec.options[i]
		end)
		return b
	elseif spec.type == "bind" then
		local b = Instance.new("TextButton")
		b.Text = spec.get().Name
		b.BackgroundColor3 = PANEL2
		b.TextColor3 = TEXT
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.TextSize = 13
		pill(b, 14)
		b.MouseButton1Click:Connect(function()
			capturingBind = { button = b, set = spec.set }
			b.Text = "..."
		end)
		return b
	elseif spec.type == "unload" then
		local b = Instance.new("TextButton")
		b.Text = "Unload"
		b.BackgroundColor3 = Color3.fromRGB(140, 40, 70)
		b.TextColor3 = TEXT
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.TextSize = 13
		pill(b, 14)
		b.MouseButton1Click:Connect(unload)
		return b
	end
	return nil
end

local function renderPane()
	clearChildren(guiPane)
	local mod = selectedModule()
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 24)
	title.Text = mod.name
	title.TextColor3 = ACCENT
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = guiPane

	if mod.rows then
		for _, spec in ipairs(mod.rows) do
			local r = Instance.new("Frame")
			r.Size = UDim2.new(1, 0, 0, 28)
			r.BackgroundTransparency = 1
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(0.45, 0, 1, 0)
			lbl.Position = UDim2.new(0, 2, 0, 0)
			lbl.Text = spec.label or ""
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextColor3 = TEXT
			lbl.BackgroundTransparency = 1
			lbl.TextSize = 13
			lbl.Parent = r
			local control = renderRow(spec)
			if control then
				control.Size = UDim2.new(0.55, -10, 1, -6)
				control.Position = UDim2.new(0.45, 0, 0, 3)
				control.Parent = r
			end
			r.Parent = guiPane
		end
	end
end

local function buildGui()
	guiRoot = Instance.new("ScreenGui")
	guiRoot.Name = "Astolfo"
	guiRoot.ResetOnSpawn = false
	guiRoot.Parent = player:FindFirstChild("PlayerGui")

	local win = Instance.new("Frame")
	win.Size = UDim2.new(0, 560, 0, 400)
	win.Position = UDim2.new(0, 10, 0, 70)
	win.BackgroundColor3 = PANEL
	win.BorderSizePixel = 0
	win.Parent = guiRoot
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = win

	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 30)
	titleBar.BackgroundColor3 = PANEL2
	titleBar.BorderSizePixel = 0
	titleBar.Parent = win

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 160, 1, 0)
	title.Position = UDim2.new(0, 10, 0, 0)
	title.Text = "ASTOLFO"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextSize = 15
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.BackgroundTransparency = 1
	title.Parent = titleBar
	local titleGrad = Instance.new("UIGradient")
	titleGrad.Color = ColorSequence.new(ACCENT2, ACCENT)
	titleGrad.Parent = title

	local version = Instance.new("TextLabel")
	version.Size = UDim2.new(0, 60, 1, 0)
	version.Position = UDim2.new(0, 90, 0, 0)
	version.Text = "v6"
	version.TextColor3 = DIM
	version.TextSize = 11
	version.BackgroundTransparency = 1
	version.TextXAlignment = Enum.TextXAlignment.Left
	version.Parent = titleBar

	local close = Instance.new("TextButton")
	close.Size = UDim2.new(0, 30, 1, 0)
	close.Position = UDim2.new(1, -30, 0, 0)
	close.Text = "x"
	close.TextColor3 = TEXT
	close.BackgroundColor3 = PANEL2
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	pill(close, 10)
	close.MouseButton1Click:Connect(toggleGui)
	close.Parent = titleBar

	guiSidebar = Instance.new("Frame")
	guiSidebar.Size = UDim2.new(0, 160, 1, -30)
	guiSidebar.Position = UDim2.new(0, 0, 0, 30)
	guiSidebar.BackgroundColor3 = PANEL
	guiSidebar.BorderSizePixel = 0
	guiSidebar.Parent = win
	local sbList = Instance.new("UIListLayout")
	sbList.Padding = UDim.new(0, 2)
	sbList.Parent = guiSidebar
	local sbPad = Instance.new("UIPadding")
	sbPad.PaddingTop = UDim.new(0, 6)
	sbPad.PaddingLeft = UDim.new(0, 6)
	sbPad.Parent = guiSidebar

	guiPane = Instance.new("Frame")
	guiPane.Size = UDim2.new(1, -160, 1, -30)
	guiPane.Position = UDim2.new(0, 160, 0, 30)
	guiPane.BackgroundColor3 = PANEL
	guiPane.BorderSizePixel = 0
	guiPane.Parent = win
	local paneList = Instance.new("UIListLayout")
	paneList.Padding = UDim.new(0, 4)
	paneList.Parent = guiPane
	local panePad = Instance.new("UIPadding")
	panePad.PaddingTop = UDim.new(0, 8)
	panePad.PaddingLeft = UDim.new(0, 8)
	panePad.PaddingRight = UDim.new(0, 8)
	panePad.Parent = guiPane

	renderSidebar()
	renderPane()

	guiRoot.Enabled = false
end

local guiVisible = false
local function toggleGui()
	guiVisible = not guiVisible
	if guiRoot then
		guiRoot.Enabled = guiVisible
	end
end

--------------------------------------------------------------------
-- Kill switch
--------------------------------------------------------------------

function unload()
	if killed then
		return
	end
	killed = true
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
	if glow then
		glow:Destroy()
		glow = nil
	end
	if guiRoot then
		guiRoot:Destroy()
	end
	-- restore hooked functions
	if inputs then
		if orig.fireLook then inputs.fireLook = orig.fireLook end
		if orig.fireHeld then inputs.fireHeld = orig.fireHeld end
	end
	if kbDelay and orig.take then
		kbDelay.take = orig.take
	end
	local p = requireShared("MCPhysics")
	if p then
		if orig.rayHit and p.Combat then p.Combat.rayHit = orig.rayHit end
		if orig.moveSpeed and p.Movement then p.Movement.moveSpeed = orig.moveSpeed end
		if orig.tick and p.Movement then p.Movement.tick = orig.tick end
	end
	restorePatches()
	if getgenv then
		getgenv().Astolfo = nil
	end
	print("[Astolfo] unloaded — all hooks and patches restored.")
end

--------------------------------------------------------------------
-- Bind handling
--------------------------------------------------------------------

connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if killed then
		return
	end
	if capturingBind then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			capturingBind.set(input.KeyCode)
			capturingBind.button.Text = input.KeyCode.Name
			capturingBind = nil
		end
		return
	end
	if gameProcessed then
		return
	end
	if input.KeyCode == BINDS.aura then
		FEATURES.aura = not FEATURES.aura
		print("[Astolfo] KillAura " .. (FEATURES.aura and "ON" or "OFF")
			.. (target and (" — target " .. target.Name .. " @ " .. math.floor(targetDist or 0)) or " — no target in range"))
	elseif input.KeyCode == BINDS.speed then
		FEATURES.speed = not FEATURES.speed
		print("[Astolfo] Speed " .. (FEATURES.speed and ("ON x" .. VALUES.speed) or "OFF"))
	elseif input.KeyCode == BINDS.kill then
		unload()
	elseif input.KeyCode == BINDS.gui then
		toggleGui()
	end
end)

--------------------------------------------------------------------
-- Init
--------------------------------------------------------------------

if getgenv then
	getgenv().Astolfo = { findTarget = findTarget, click = click, candidates = targetCandidates }
end

buildGui()

task.spawn(function()
	task.wait(1)
	print("[Astolfo][check] hooks: fireLook=" .. tostring(hookStatus.fireLook)
		.. " rayHit=" .. tostring(hookStatus.rayHit)
		.. " moveSpeed=" .. tostring(hookStatus.moveSpeed)
		.. " kbTake=" .. tostring(hookStatus.kbTake)
		.. " tick=" .. tostring(hookStatus.tick)
		.. " fireHeld=" .. tostring(hookStatus.fireHeld))
	print("[Astolfo][check] patches: " .. tostring(patchResult))
	print("[Astolfo] Ready — F KillAura | G Speed | L unload | RightShift GUI")
end)
