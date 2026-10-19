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
	esp = true,
	watermark = true,
}
local VALUES = {
	cps = 10, -- 1..20
	range = 60, -- studs
	reach = 3.2, -- 2.5..4 (server tolerance is 3.3 — above gets flagged)
	attackDist = 3.4, -- click only when closer than this
	speed = 2.5, -- 1..5 multiplier
	kbKeep = 0, -- 0..100: % of incoming knockback kept (0 = none)
	targets = "All", -- All / Players / Bots
}
local BINDS = {
	aura = Enum.KeyCode.F,
	speed = Enum.KeyCode.G,
	kill = Enum.KeyCode.L,
	gui = Enum.KeyCode.RightShift,
}

local WATERMARK_TEXT = "Astolfo"

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

local function findTarget()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local best, bestDist, bestPos
	for _, m in ipairs(targetCandidates()) do
		local h = findHead(m)
		if h and h.Parent then
			local d = (h.Position - camPos).Magnitude
			if d <= VALUES.range and d < (bestDist or math.huge) then
				best, bestDist, bestPos = m, d, h.Position
			end
		end
	end
	return best, bestDist, bestPos
end

--------------------------------------------------------------------
-- Modules + originals (everything restored by unload)
--------------------------------------------------------------------

local function requireShared(name)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local mod = shared and shared:FindFirstChild(name)
	if not mod then
		return nil
	end
	local ok, res = pcall(require, mod)
	return ok and typeof(res) == "table" and res or nil
end

local physics = requireShared("MCPhysics")
local aimAssist = requireShared("AimAssist")
local inputs = requireShared("Net/Inputs")
local kbDelay = requireShared("KbDelay")

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
-- The game's own loop fires fireLook(handles, realYaw, realPitch) each frame; we
-- rewrite the values toward the target, bounded so the anti-cheat's aim snap
-- budget (35 deg/tick) is never exceeded. Camera/screen stay on the real look.
local AIM_MAX_DEG_PER_FRAME = 8
if inputs and type(inputs.fireLook) == "function" and aimAssist then
	orig.fireLook = inputs.fireLook
	inputs.fireLook = function(handles, yaw, pitch)
		if not killed and FEATURES.aura and targetPos then
			local ex = player:GetAttribute("X")
			local ey = player:GetAttribute("Y")
			local ez = player:GetAttribute("Z")
			if ex then
				local cy = targetPos.Y - 0.8 -- head -> box center
				local dyaw, dpitch = aimAssist.anglesTo(ex, ey + 1.62, ez, targetPos.X, cy, targetPos.Z)
				local dY = ((dyaw - yaw + 180) % 360) - 180
				local dP = math.clamp(dpitch - pitch, -AIM_MAX_DEG_PER_FRAME, AIM_MAX_DEG_PER_FRAME)
				yaw = yaw + math.clamp(dY, -AIM_MAX_DEG_PER_FRAME, AIM_MAX_DEG_PER_FRAME)
				pitch = pitch + dP
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
		if not killed and FEATURES.aura and targetPos and box then
			local cx = (box.minX + box.maxX) / 2
			local cy = (box.minY + box.maxY) / 2
			local cz = (box.minZ + box.maxZ) / 2
			local off = Vector3.new(cx - targetPos.X, cy - (targetPos.Y - 0.8), cz - targetPos.Z).Magnitude
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

-- Bhop: force Jump on the held input while moving.
if inputs and type(inputs.fireHeld) == "function" then
	orig.fireHeld = inputs.fireHeld
	inputs.fireHeld = function(handles, held)
		if not killed and FEATURES.bhop and held and UserInputService:GetFocusedTextBox() == nil then
			local moving = UserInputService:IsKeyDown(Enum.KeyCode.W)
				or UserInputService:IsKeyDown(Enum.KeyCode.A)
				or UserInputService:IsKeyDown(Enum.KeyCode.S)
				or UserInputService:IsKeyDown(Enum.KeyCode.D)
			if moving then
				held.Jump = true
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
local box, label, wm
local tracerPool = {}

do
	local ok = pcall(function()
		if not Drawing then
			error("no Drawing")
		end
		box = Drawing.new("Square")
		box.Thickness = 2
		box.Filled = false
		box.Color = Color3.fromRGB(255, 60, 60)
		box.Visible = false
		drawings[#drawings + 1] = box

		label = Drawing.new("Text")
		label.Size = 16
		label.Center = true
		label.Outline = true
		label.Color = Color3.fromRGB(255, 60, 60)
		label.Visible = false
		drawings[#drawings + 1] = label

		wm = Drawing.new("Text")
		wm.Text = WATERMARK_TEXT
		wm.Size = 40
		wm.Center = false
		wm.Outline = true
		wm.Color = Color3.fromRGB(40, 170, 255)
		wm.Visible = FEATURES.watermark
		drawings[#drawings + 1] = wm

		for _ = 1, 24 do
			local line = Drawing.new("Line")
			line.Thickness = 1
			line.Color = Color3.fromRGB(255, 90, 90)
			line.Transparency = 0.4
			line.Visible = false
			drawings[#drawings + 1] = line
			tracerPool[#tracerPool + 1] = line
		end
	end)
	if not ok then
		warn("[Astolfo] Drawing API unavailable — no ESP/watermark.")
	end
end

local wmClock, wmX = 0, -300
local function stepWatermark(dt)
	if not wm or not wm.Visible then
		return
	end
	dt = dt or 0
	wmClock = wmClock + dt
	local screenW = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X) or 1920
	local width = math.max(#wm.Text * 40 * 0.6, 120)
	wmX = wmX + 140 * dt
	if wmX > screenW then
		wmX = -width
	end
	local t = (math.sin(wmClock * 2) + 1) / 2
	wm.Position = Vector2.new(wmX, 10)
	wm.Size = 40 + t * 4
	wm.Color = Color3.fromRGB(40, 170, 255):Lerp(Color3.fromRGB(6, 30, 90), t)
end

local function step(dt)
	local camera = Workspace.CurrentCamera
	target, targetDist, targetPos = findTarget()

	stepWatermark(dt)

	local screenPos
	if targetPos and camera then
		local p, onScreen = camera:WorldToViewportPoint(targetPos)
		screenPos = onScreen and p or nil
	end

	if box and label then
		if FEATURES.esp and screenPos then
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

	if FEATURES.esp and camera then
		local cands = targetCandidates()
		local bottom = camera.ViewportSize.Y
		for i = 1, #tracerPool do
			local line = tracerPool[i]
			local m = cands[i]
			if m then
				local h = findHead(m)
				if h and h.Parent then
					local p, onScreen = camera:WorldToViewportPoint(h.Position)
					if onScreen then
						line.From = Vector2.new(p.X, p.Y)
						line.To = Vector2.new(p.X, bottom - 4)
						line.Visible = true
					else
						line.Visible = false
					end
				else
					line.Visible = false
				end
			else
				line.Visible = false
			end
		end
	end

	if FEATURES.aura and targetPos and camera
		and (targetDist or math.huge) <= VALUES.attackDist
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

local guiRoot, guiFrame
local capturingBind = nil

local function guiButton(text, color)
	local b = Instance.new("TextButton")
	b.Text = text
	b.BackgroundColor3 = color or Color3.fromRGB(45, 45, 55)
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.TextSize = 14
	return b
end

local function addRow(name, control)
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, 0, 0, 26)
	r.BackgroundTransparency = 1
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.45, 0, 1, 0)
	lbl.Position = UDim2.new(0, 6, 0, 0)
	lbl.Text = name
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
	lbl.BackgroundTransparency = 1
	lbl.TextSize = 14
	lbl.Parent = r
	control.Size = UDim2.new(0.55, -6, 1, -4)
	control.Position = UDim2.new(0.45, 0, 0, 2)
	control.Parent = r
	r.Parent = guiFrame
	return control
end

local function addToggleRow(name, get, set)
	local b = guiButton("")
	local function refresh()
		local on = get()
		b.Text = on and "ON" or "OFF"
		b.BackgroundColor3 = on and Color3.fromRGB(40, 140, 60) or Color3.fromRGB(120, 40, 40)
	end
	refresh()
	b.MouseButton1Click:Connect(function()
		set(not get())
		refresh()
	end)
	addRow(name, b)
end

local function addSliderRow(name, get, set, min, max, step)
	local b = guiButton(tostring(get()))
	local function refresh()
		b.Text = tostring(get())
	end
	b.MouseButton1Click:Connect(function()
		set(math.min(max, get() + step))
		refresh()
	end)
	b.MouseButton2Click:Connect(function()
		set(math.max(min, get() - step))
		refresh()
	end)
	addRow(name, b)
end

local function addCycleRow(name, get, set, options)
	local b = guiButton(get())
	local i = 1
	for idx, o in ipairs(options) do
		if o == get() then
			i = idx
		end
	end
	b.MouseButton1Click:Connect(function()
		i = i % #options + 1
		set(options[i])
		b.Text = options[i]
	end)
	addRow(name, b)
end

local function addBindRow(name, getKey, setKey)
	local b = guiButton(getKey().Name)
	b.MouseButton1Click:Connect(function()
		capturingBind = { button = b, set = setKey }
		b.Text = "..."
	end)
	addRow(name, b)
end

local function buildGui()
	guiRoot = Instance.new("ScreenGui")
	guiRoot.Name = "AstolfoGUI"
	guiRoot.ResetOnSpawn = false
	guiRoot.Parent = player:FindFirstChild("PlayerGui")

	guiFrame = Instance.new("Frame")
	guiFrame.Size = UDim2.new(0, 300, 0, 0)
	guiFrame.AutomaticSize = Enum.AutomaticSize.Y
	guiFrame.Position = UDim2.new(0, 10, 0, 80)
	guiFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	guiFrame.BorderSizePixel = 0
	guiFrame.Parent = guiRoot

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Text = "Astolfo"
	title.TextColor3 = Color3.fromRGB(90, 180, 255)
	title.TextSize = 18
	title.Font = Enum.Font.GothamBold
	title.BackgroundTransparency = 1
	title.Parent = guiFrame

	local list = Instance.new("UIListLayout")
	list.Parent = guiFrame

	addToggleRow("KillAura", function() return FEATURES.aura end, function(v)
		FEATURES.aura = v
		print("[Astolfo] KillAura " .. (v and "ON" or "OFF"))
	end)
	addSliderRow("CPS", function() return VALUES.cps end, function(v) VALUES.cps = v end, 1, 20, 1)
	addSliderRow("Range", function() return VALUES.range end, function(v) VALUES.range = v end, 10, 60, 5)
	addSliderRow("Reach", function() return VALUES.reach end, function(v)
		VALUES.reach = v
		applyReach(v)
	end, 2.5, 4, 0.1)
	addSliderRow("AttackDist", function() return VALUES.attackDist end, function(v) VALUES.attackDist = v end, 2.5, 4.5, 0.1)
	addCycleRow("Targets", function() return VALUES.targets end, function(v) VALUES.targets = v end, { "All", "Players", "Bots" })
	addToggleRow("Speed", function() return FEATURES.speed end, function(v)
		FEATURES.speed = v
		print("[Astolfo] Speed " .. (v and ("ON x" .. VALUES.speed) or "OFF"))
	end)
	addSliderRow("Speed x", function() return VALUES.speed end, function(v) VALUES.speed = v end, 1, 5, 0.5)
	addToggleRow("Velocity", function() return FEATURES.velocity end, function(v)
		FEATURES.velocity = v
		print("[Astolfo] Velocity " .. (v and "ON" or "OFF"))
	end)
	addSliderRow("KB keep %", function() return VALUES.kbKeep end, function(v) VALUES.kbKeep = v end, 0, 100, 10)
	addToggleRow("NoSlow", function() return FEATURES.noslow end, function(v) FEATURES.noslow = v end)
	addToggleRow("Bhop", function() return FEATURES.bhop end, function(v) FEATURES.bhop = v end)
	addToggleRow("ESP", function() return FEATURES.esp end, function(v) FEATURES.esp = v end)
	addToggleRow("Watermark", function() return FEATURES.watermark end, function(v)
		FEATURES.watermark = v
		if wm then
			wm.Visible = v
		end
	end)
	addBindRow("Aura bind", function() return BINDS.aura end, function(k) BINDS.aura = k end)
	addBindRow("Speed bind", function() return BINDS.speed end, function(k) BINDS.speed = k end)
	addBindRow("Kill bind", function() return BINDS.kill end, function(k) BINDS.kill = k end)
	addBindRow("GUI bind", function() return BINDS.gui end, function(k) BINDS.gui = k end)

	local unloadBtn = guiButton("Unload (restore everything)")
	unloadBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
	unloadBtn.MouseButton1Click:Connect(unload)
	addRow("", unloadBtn)

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
