-- gui — the Astolfo menu: pastel palette, pill buttons, sidebar + settings pane
local S = getgenv().Astolfo

local ACCENT = Color3.fromRGB(255, 158, 208) -- bubblegum pink
local ACCENT2 = Color3.fromRGB(180, 155, 255) -- lavender
local PANEL = Color3.fromRGB(11, 11, 15) -- deep black
local PANEL2 = Color3.fromRGB(22, 22, 30)
local TEXT = Color3.fromRGB(235, 235, 240)
local DIM = Color3.fromRGB(150, 140, 160)

S.guiRoot, S.guiSidebar, S.guiPane = nil, nil, nil
S.capturingBind = nil
local guiSelected = { cat = "Combat", name = "KillAura" }

local function pill(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 14)
	c.Parent = inst
end

local MODULES = {
	{ cat = "Combat", name = "KillAura", get = function() return S.FEATURES.aura end, set = function(v)
		S.FEATURES.aura = v
		print("[Astolfo] KillAura " .. (v and "ON" or "OFF"))
	end, bind = function() return S.BINDS.aura end, rows = {
		{ type = "slider", label = "CPS", get = function() return S.VALUES.cps end, set = function(v) S.VALUES.cps = v end, min = 1, max = 20, step = 1 },
		{ type = "slider", label = "Range", get = function() return S.VALUES.range end, set = function(v) S.VALUES.range = v end, min = 10, max = 60, step = 5 },
		{ type = "slider", label = "Reach", get = function() return S.VALUES.reach end, set = function(v)
			S.VALUES.reach = v
			S.applyReach(v)
		end, min = 2.5, max = 4, step = 0.1 },
		{ type = "slider", label = "AttackDist", get = function() return S.VALUES.attackDist end, set = function(v) S.VALUES.attackDist = v end, min = 2.5, max = 4.5, step = 0.1 },
		{ type = "cycle", label = "Targets", get = function() return S.VALUES.targets end, set = function(v) S.VALUES.targets = v end, options = { "All", "Players", "Bots" } },
		{ type = "cycle", label = "Aim", get = function() return S.VALUES.aimMode end, set = function(v) S.VALUES.aimMode = v end, options = { "Instant", "Smooth" } },
		{ type = "toggle", label = "Glow target", get = function() return S.FEATURES.glow end, set = function(v) S.FEATURES.glow = v end },
		{ type = "toggle", label = "TargetStrafe", get = function() return S.FEATURES.strafe end, set = function(v)
			S.FEATURES.strafe = v
			print("[Astolfo] TargetStrafe " .. (v and "ON" or "OFF"))
		end },
	} },
	{ cat = "Combat", name = "Velocity", get = function() return S.FEATURES.velocity end, set = function(v)
		S.FEATURES.velocity = v
		print("[Astolfo] Velocity " .. (v and "ON" or "OFF"))
	end, rows = {
		{ type = "slider", label = "KB keep %", get = function() return S.VALUES.kbKeep end, set = function(v) S.VALUES.kbKeep = v end, min = 0, max = 100, step = 10 },
	} },
	{ cat = "Movement", name = "Speed", get = function() return S.FEATURES.speed end, set = function(v)
		S.FEATURES.speed = v
		print("[Astolfo] Speed " .. (v and ("ON x" .. S.VALUES.speed) or "OFF"))
	end, bind = function() return S.BINDS.speed end, rows = {
		{ type = "slider", label = "Multiplier", get = function() return S.VALUES.speed end, set = function(v) S.VALUES.speed = v end, min = 1, max = 5, step = 0.5 },
	} },
	{ cat = "Movement", name = "Bhop", get = function() return S.FEATURES.bhop end, set = function(v) S.FEATURES.bhop = v end },
	{ cat = "Movement", name = "NoSlow", get = function() return S.FEATURES.noslow end, set = function(v) S.FEATURES.noslow = v end },
	{ cat = "Render", name = "ESP", get = function() return S.FEATURES.esp end, set = function(v) S.FEATURES.esp = v end },
	{ cat = "Render", name = "Watermark", get = function() return S.FEATURES.watermark end, set = function(v)
		S.FEATURES.watermark = v
		S.setWmVisible(v)
	end },
	{ cat = "Client", name = "Keybinds", rows = {
		{ type = "bind", label = "Aura", get = function() return S.BINDS.aura end, set = function(k) S.BINDS.aura = k end },
		{ type = "bind", label = "Speed", get = function() return S.BINDS.speed end, set = function(k) S.BINDS.speed = k end },
		{ type = "bind", label = "Kill", get = function() return S.BINDS.kill end, set = function(k) S.BINDS.kill = k end },
		{ type = "bind", label = "GUI", get = function() return S.BINDS.gui end, set = function(k) S.BINDS.gui = k end },
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
	clearChildren(S.guiSidebar)
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
		catBtn.Parent = S.guiSidebar

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
				row.Parent = S.guiSidebar
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
			S.capturingBind = { button = b, set = spec.set }
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
		b.MouseButton1Click:Connect(S.unload)
		return b
	end
	return nil
end

local function renderPane()
	clearChildren(S.guiPane)
	local mod = selectedModule()
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 24)
	title.Text = mod.name
	title.TextColor3 = ACCENT
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = S.guiPane

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
			r.Parent = S.guiPane
		end
	end
end

function S.buildGui()
	S.guiRoot = Instance.new("ScreenGui")
	S.guiRoot.Name = "Astolfo"
	S.guiRoot.ResetOnSpawn = false
	S.guiRoot.Parent = S.player:FindFirstChild("PlayerGui")

	local win = Instance.new("Frame")
	win.Size = UDim2.new(0, 560, 0, 400)
	win.Position = UDim2.new(0, 10, 0, 70)
	win.BackgroundColor3 = PANEL
	win.BorderSizePixel = 0
	win.Parent = S.guiRoot
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
	close.MouseButton1Click:Connect(S.toggleGui)
	close.Parent = titleBar

	S.guiSidebar = Instance.new("Frame")
	S.guiSidebar.Size = UDim2.new(0, 160, 1, -30)
	S.guiSidebar.Position = UDim2.new(0, 0, 0, 30)
	S.guiSidebar.BackgroundColor3 = PANEL
	S.guiSidebar.BorderSizePixel = 0
	S.guiSidebar.Parent = win
	local sbList = Instance.new("UIListLayout")
	sbList.Padding = UDim.new(0, 2)
	sbList.Parent = S.guiSidebar
	local sbPad = Instance.new("UIPadding")
	sbPad.PaddingTop = UDim.new(0, 6)
	sbPad.PaddingLeft = UDim.new(0, 6)
	sbPad.Parent = S.guiSidebar

	S.guiPane = Instance.new("Frame")
	S.guiPane.Size = UDim2.new(1, -160, 1, -30)
	S.guiPane.Position = UDim2.new(0, 160, 0, 30)
	S.guiPane.BackgroundColor3 = PANEL
	S.guiPane.BorderSizePixel = 0
	S.guiPane.Parent = win
	local paneList = Instance.new("UIListLayout")
	paneList.Padding = UDim.new(0, 4)
	paneList.Parent = S.guiPane
	local panePad = Instance.new("UIPadding")
	panePad.PaddingTop = UDim.new(0, 8)
	panePad.PaddingLeft = UDim.new(0, 8)
	panePad.PaddingRight = UDim.new(0, 8)
	panePad.Parent = S.guiPane

	renderSidebar()
	renderPane()

	S.guiRoot.Enabled = false
end

local guiVisible = false
function S.toggleGui()
	guiVisible = not guiVisible
	if S.guiRoot then
		S.guiRoot.Enabled = guiVisible
	end
end
