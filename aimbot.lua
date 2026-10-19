-- AimBot — face the nearest player with your head, and click to attack.
-- ponytail: this game has no Humanoids and clicking fires no remote (probed), so hits are
-- resolved by the game's own controller when it sees a real mouse click. Aiming = set your
-- head CFrame toward the target each frame; attacking = synthesize a real click.

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------

local CONFIG = {
	BIND = Enum.KeyCode.F, -- toggle aim+click
	KILL_BIND = Enum.KeyCode.L, -- unload the script entirely (kill switch)
	SPEED_BIND = Enum.KeyCode.G, -- toggle movement speed boost
	RANGE = 60, -- studs
	INCLUDE_BOTS = true, -- `MCBody Bot####` models are valid targets
	LOCAL_MODEL_NAME = "MCBody", -- your own avatar model (others are `MCBody <id>`)
	HEAD_RUN_PRIORITY = Enum.RenderPriority.Last.Value - 1, -- run after everything so the turn sticks
	AIM_WHOLE_BODY = true, -- yaw the body too, not just the head
	AUTO_CLICK = true, -- click at the target while aiming
	CLICK_INTERVAL = 0.2, -- seconds between clicks
	SPEED_BONUS = 30, -- extra studs/second while moving (boost toggled with G)
	WATERMARK = "Astolfo", -- top-of-screen scrolling text
	WATERMARK_ON = true,
	WATERMARK_SIZE = 40,
	WATERMARK_SPEED = 140, -- pixels/second, left to right
	WATERMARK_BRIGHT = Color3.fromRGB(40, 170, 255), -- light blue
	WATERMARK_DARK = Color3.fromRGB(6, 30, 90), -- dark blue
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

local player = Players.LocalPlayer
if not player then
	warn("[Aim] Needs to run as a client local script.")
	return
end

--------------------------------------------------------------------
-- Finding your own model + head
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
	local best, bestY = nil, -math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Position.Y > bestY then
			best, bestY = p, p.Position.Y
		end
	end
	return best
end

-- Your avatar is `MCBody <yourUserId>`. A plain `MCBody` also exists but it's an
-- unpositioned template rig (every part sits at 0,0,0) — aiming that does nothing.
local function localModel()
	local byId = Workspace:FindFirstChild(CONFIG.LOCAL_MODEL_NAME .. " " .. tostring(player.UserId))
	if byId and byId:IsA("Model") then
		return byId
	end
	local exact = Workspace:FindFirstChild(CONFIG.LOCAL_MODEL_NAME)
	if exact and exact:IsA("Model") then
		local h = findHead(exact)
		if h and h.Position.Magnitude > 0.01 then
			return exact
		end
	end
	return byId
end

local ROOT_NAMES = { "Torso", "Root", "RootPart", "UpperTorso", "HumanoidRootPart", "Body", "Chest" }

-- the part that carries the avatar's yaw (torso-ish), if any
local function findRoot(model)
	if not model then
		return nil
	end
	local pp = model.PrimaryPart
	if pp and pp:IsA("BasePart") then
		return pp
	end
	for _, n in ipairs(ROOT_NAMES) do
		local p = model:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

--------------------------------------------------------------------
-- Target selection (other `MCBody*` models)
--------------------------------------------------------------------

local function isTargetBody(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("Model") then
		return false
	end
	if inst.Name == CONFIG.LOCAL_MODEL_NAME then -- template rig
		return false
	end
	if inst.Name == CONFIG.LOCAL_MODEL_NAME .. " " .. tostring(player.UserId) then -- you
		return false
	end
	if inst.Name:sub(1, 6) ~= "MCBody" then
		return false
	end
	if not CONFIG.INCLUDE_BOTS and inst.Name:find("Bot") then
		return false
	end
	return true
end

local function findTarget()
	local myHead = findHead(localModel())
	local myPos = myHead and myHead.Position or Vector3.zero
	local best, bestDist, bestHead
	for _, m in ipairs(Workspace:GetChildren()) do
		if isTargetBody(m) then
			local h = findHead(m)
			if h and h.Parent then
				local d = (h.Position - myPos).Magnitude
				if d <= CONFIG.RANGE and d < (bestDist or math.huge) then
					best, bestDist, bestHead = m, d, h
				end
			end
		end
	end
	return best, bestDist, bestHead
end

--------------------------------------------------------------------
-- The aim function
--------------------------------------------------------------------

-- Rotate `part` (your head) so its front faces `targetHead`, keeping its position.
local function AimPart(part, targetHead)
	if not part or not part.Parent or not targetHead or not targetHead.Parent then
		return false
	end
	part.CFrame = CFrame.lookAt(part.Position, targetHead.Position)
	return true
end

local function AimAt(target)
	return AimPart(findHead(localModel()), findHead(target))
end

-- Turn your whole avatar toward `targetHead`: head looks fully, body yaws (keeps it upright).
local function AimModel(model, targetHead)
	if not model or not targetHead or not targetHead.Parent then
		return false
	end
	local did = false
	local head = findHead(model)
	if head and head.Parent then
		head.CFrame = CFrame.lookAt(head.Position, targetHead.Position)
		did = true
	end
	if CONFIG.AIM_WHOLE_BODY then
		local root = findRoot(model)
		if root and root.Parent and root ~= head then
			local dir = targetHead.Position - root.Position
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0.01 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
				did = true
			end
		end
	end
	return did
end

--------------------------------------------------------------------
-- Clicking (attack)
--------------------------------------------------------------------

local VirtualInputManager = game:GetService("VirtualInputManager")

-- fire a real left click; prefers executor mouse helpers, falls back to VIM.
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

-- exported for manual use
if getgenv then
	getgenv().Aim = { AimPart = AimPart, AimAt = AimAt, AimModel = AimModel, findTarget = findTarget, findHead = findHead, findRoot = findRoot, click = click }
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
-- Per-frame loop
--------------------------------------------------------------------

local enabled = false
local speedOn = false
local target, targetHead, targetDist
local lastClick = 0

-- shove the avatar forward with WASD, camera-relative. No Humanoid, so we move the root.
local function applySpeed(dt, model, camera)
	if not speedOn or not model or not camera then
		return
	end
	local dir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		dir = dir + camera.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		dir = dir - camera.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		dir = dir + camera.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		dir = dir - camera.CFrame.RightVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	local root = findRoot(model) or model.PrimaryPart
	if not root then
		return
	end
	root.CFrame = root.CFrame + dir.Unit * (CONFIG.SPEED_BONUS * dt)
end

-- watermark: scrolls left->right forever, colour pulses between light and dark blue
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
	local t = (math.sin(wmClock * 2) + 1) / 2 -- 0..1
	wm.Position = Vector2.new(wmX, 10)
	wm.Size = CONFIG.WATERMARK_SIZE + t * 4 -- slight pulse
	wm.Color = CONFIG.WATERMARK_BRIGHT:Lerp(CONFIG.WATERMARK_DARK, t)
end

-- start off the left edge so it visually enters from the left
wmX = -300

local function step(dt)
	local camera = Workspace.CurrentCamera
	target, targetDist, targetHead = findTarget()

	local screenPos
	if targetHead and camera then
		local p, onScreen = camera:WorldToViewportPoint(targetHead.Position)
		screenPos = onScreen and p or nil
	end

	stepWatermark(dt)

	local model = localModel()
	if dt then
		applySpeed(dt, model, camera)
	end

	if enabled and targetHead then
		AimModel(model, targetHead)
		if CONFIG.AUTO_CLICK and tick() - lastClick >= CONFIG.CLICK_INTERVAL then
			lastClick = tick()
			local cx = camera and camera.ViewportSize.X / 2 or 0
			local cy = camera and camera.ViewportSize.Y / 2 or 0
			if screenPos then
				cx, cy = screenPos.X, screenPos.Y
			end
			click(cx, cy)
		end
	end

	if not (box and label) then
		return
	end
	if not target or not targetHead or not screenPos then
		box.Visible = false
		label.Visible = false
		return
	end
	local dist = targetDist or 0
	local size = math.clamp(900 / math.max(dist, 1), 24, 260)
	box.Size = Vector2.new(size, size * 1.35)
	box.Position = Vector2.new(screenPos.X - size / 2, screenPos.Y - size * 0.68)
	box.Visible = true
	label.Position = Vector2.new(screenPos.X, screenPos.Y - size * 0.78 - 14)
	label.Text = target.Name .. "  [" .. math.floor(dist) .. "]"
	label.Visible = true
end

local connections = {}
if RunService.BindToRenderStep then
	RunService:BindToRenderStep(RENDER_NAME, CONFIG.HEAD_RUN_PRIORITY, step)
else
	connections[#connections + 1] = RunService.RenderStepped:Connect(step)
end

--------------------------------------------------------------------
-- Kill switch: fully unloads the script (unbind render step, drop
-- drawings, disconnect inputs, clear the exported table)
--------------------------------------------------------------------

local function unload()
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
	if getgenv then
		getgenv().Aim = nil
	end
	print("[Aim] script killed — unhooked, drawings removed.")
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
		print("[Aim] " .. (enabled and "ON" or "OFF")
			.. (target and (" — target " .. target.Name .. " @ " .. math.floor(targetDist or 0)) or " — no target in range"))
	elseif input.KeyCode == CONFIG.KILL_BIND then
		unload()
	elseif input.KeyCode == CONFIG.SPEED_BIND then
		speedOn = not speedOn
		print("[Aim] speed boost " .. (speedOn and "ON (+" .. CONFIG.SPEED_BONUS .. " studs/s)" or "OFF"))
	end
end)

--------------------------------------------------------------------
-- SELF CHECK
--------------------------------------------------------------------

task.spawn(function()
	task.wait(1)
	local a, b = Vector3.new(0, 0, 0), Vector3.new(1, 0, 0)
	local lv = CFrame.lookAt(a, b).LookVector
	assert((lv - (b - a).Unit).Magnitude < 1e-4, "[Aim] lookAt math broken")

	local model = localModel()
	local head = findHead(model)
	print("[Aim][check] own model: " .. (model and model.Name or "NOT FOUND")
		.. "  head: " .. (head and (head.Name .. " @" .. tostring(head.Position)) or "NOT FOUND"))
	print("[Aim][check] expected avatar name: " .. CONFIG.LOCAL_MODEL_NAME .. " " .. tostring(player.UserId))
	local names = {}
	for _, m in ipairs(Workspace:GetChildren()) do
		if isTargetBody(m) then
			names[#names + 1] = m.Name
		end
	end
	print("[Aim][check] targets: " .. #names .. " (" .. table.concat(names, ", ") .. ")")
	-- model anatomy, so we can see the real part names/positions
	local parts, shown = {}, 0
	for _, p in ipairs(model and model:GetDescendants() or {}) do
		if p:IsA("BasePart") and shown < 12 then
			shown = shown + 1
			parts[#parts + 1] = p.Name .. "@" .. tostring(p.Position)
		end
	end
	print("[Aim][check] parts: " .. (shown > 0 and table.concat(parts, " ") or "NONE"))
	print("[Aim][check] root: " .. (findRoot(model) and findRoot(model).Name or "NOT FOUND")
		.. "  primary: " .. (model and model.PrimaryPart and model.PrimaryPart.Name or "nil"))
	print("[Aim][check] humanoid: " .. tostring(model and model:FindFirstChildWhichIsA("Humanoid") ~= nil)
		.. "  parts: " .. tostring(model and #model:GetChildren() or 0))
	print("[Aim][check] clicker: mouse1click=" .. tostring(type(mouse1click) == "function")
		.. " mouse1press=" .. tostring(type(mouse1press) == "function") .. " vim=true")
	print("[Aim] Ready — " .. CONFIG.BIND.Name .. " aim+click | " .. CONFIG.SPEED_BIND.Name
		.. " speed boost | " .. CONFIG.KILL_BIND.Name .. " kill script")
end)
