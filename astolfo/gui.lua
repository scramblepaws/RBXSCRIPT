-- gui — Luna menu (glass, themeable)
local S = getgenv().Astolfo

local ok, Luna = pcall(function()
	return loadstring(game:HttpGet(
		"https://raw.githubusercontent.com/Nebula-Softworks/Luna-Interface-Suite/refs/heads/master/source.lua",
		true))()
end)
if not ok or type(Luna) ~= "table" then
	print("[Astolfo] Luna failed to load — menu unavailable")
	return
end
S.Luna = Luna

-- every element is wrapped so a bad one prints instead of killing the menu
local function safe(label, f)
	local ok, err = pcall(f)
	if not ok then
		print("[Astolfo] gui FAILED " .. label .. ": " .. tostring(err))
	end
end

local Window
safe("window", function()
	Window = Luna:CreateWindow({
		Name = "astolfo",
		Subtitle = "v6",
		LogoID = "82795327169782",
		LoadingEnabled = true,
		LoadingTitle = "astolfo",
		LoadingSubtitle = "pastel pvp client",
		ConfigSettings = { RootFolder = nil, ConfigFolder = "Astolfo" },
		KeySystem = false,
	})
end)
if not Window then
	print("[Astolfo] Luna window missing — menu unavailable")
	return
end
S.Window = Window
Window.Bind = Enum.KeyCode.RightShift

function S.buildGui() end

local function printOn(name, v)
	print("[Astolfo] " .. name .. " " .. (v and "ON" or "OFF"))
end

local combat = Window:CreateTab({ Name = "Combat", Icon = "shield", ImageSource = "Material", ShowTitle = false })
local movement = Window:CreateTab({ Name = "Movement", Icon = "directions_run", ImageSource = "Material", ShowTitle = false })
local render = Window:CreateTab({ Name = "Render", Icon = "visibility", ImageSource = "Material", ShowTitle = false })
local client = Window:CreateTab({ Name = "Client", Icon = "settings", ImageSource = "Material", ShowTitle = false })

-- Combat -----------------------------------------------------------------
safe("section combat killaura", function() combat:CreateSection("KillAura") end)
safe("toggle KillAura", function()
	combat:CreateToggle({ Name = "KillAura", CurrentValue = S.FEATURES.aura,
		Callback = function(v) S.FEATURES.aura = v; printOn("KillAura", v) end }, "aura")
end)
safe("slider CPS", function()
	combat:CreateSlider({ Name = "CPS", Range = { 1, 20 }, Increment = 1, CurrentValue = S.VALUES.cps,
		Callback = function(v) S.VALUES.cps = v end }, "cps")
end)
safe("slider Range", function()
	combat:CreateSlider({ Name = "Range", Range = { 10, 60 }, Increment = 5, CurrentValue = S.VALUES.range,
		Callback = function(v) S.VALUES.range = v end }, "range")
end)
safe("slider Reach", function()
	combat:CreateSlider({ Name = "Reach", Range = { 2.5, 4 }, Increment = 0.1, CurrentValue = S.VALUES.reach,
		Callback = function(v)
			S.VALUES.reach = v
			S.applyReach(v)
		end }, "reach")
end)
safe("slider AttackDist", function()
	combat:CreateSlider({ Name = "AttackDist", Range = { 2.5, 4.5 }, Increment = 0.1, CurrentValue = S.VALUES.attackDist,
		Callback = function(v) S.VALUES.attackDist = v end }, "attackdist")
end)
safe("slider FOV", function()
	combat:CreateSlider({ Name = "FOV (360 = off)", Range = { 30, 360 }, Increment = 10, CurrentValue = S.VALUES.fov,
		Callback = function(v) S.VALUES.fov = v end }, "fov")
end)
safe("dropdown Targets", function()
	combat:CreateDropdown({ Name = "Targets", Options = { "All", "Players", "Bots" }, CurrentOption = { S.VALUES.targets }, MultipleOptions = false,
		Callback = function(v) S.VALUES.targets = v end }, "targets")
end)
safe("dropdown Aim", function()
	combat:CreateDropdown({ Name = "Aim", Options = { "Instant", "Smooth" }, CurrentOption = { S.VALUES.aimMode }, MultipleOptions = false,
		Callback = function(v) S.VALUES.aimMode = v end }, "aim")
end)
safe("toggle Glow", function()
	combat:CreateToggle({ Name = "Glow target", CurrentValue = S.FEATURES.glow,
		Callback = function(v) S.FEATURES.glow = v end }, "glow")
end)
safe("toggle TargetStrafe", function()
	combat:CreateToggle({ Name = "TargetStrafe", CurrentValue = S.FEATURES.strafe,
		Callback = function(v) S.FEATURES.strafe = v; printOn("TargetStrafe", v) end }, "strafe")
end)

safe("section velocity", function() combat:CreateSection("Velocity") end)
safe("toggle Velocity", function()
	combat:CreateToggle({ Name = "Velocity", CurrentValue = S.FEATURES.velocity,
		Callback = function(v) S.FEATURES.velocity = v; printOn("Velocity", v) end }, "velocity")
end)
safe("slider KB keep", function()
	combat:CreateSlider({ Name = "KB keep %", Range = { 0, 100 }, Increment = 10, CurrentValue = S.VALUES.kbKeep,
		Callback = function(v) S.VALUES.kbKeep = v end }, "kbkeep")
end)

safe("section autoclicker", function() combat:CreateSection("AutoClicker") end)
safe("toggle AutoClicker", function()
	combat:CreateToggle({ Name = "AutoClicker", CurrentValue = S.FEATURES.autoclick,
		Callback = function(v) S.FEATURES.autoclick = v; printOn("AutoClicker", v) end }, "autoclick")
end)

-- Movement ---------------------------------------------------------------
safe("toggle Speed", function()
	movement:CreateToggle({ Name = "Speed", CurrentValue = S.FEATURES.speed,
		Callback = function(v)
			S.FEATURES.speed = v
			print("[Astolfo] Speed " .. (v and ("ON x" .. S.VALUES.speed) or "OFF"))
		end }, "speed")
end)
safe("slider Multiplier", function()
	movement:CreateSlider({ Name = "Multiplier", Range = { 1, 5 }, Increment = 0.5, CurrentValue = S.VALUES.speed,
		Callback = function(v) S.VALUES.speed = v end }, "speedmult")
end)
safe("toggle Bhop", function()
	movement:CreateToggle({ Name = "Bhop", CurrentValue = S.FEATURES.bhop,
		Callback = function(v) S.FEATURES.bhop = v end }, "bhop")
end)
safe("toggle NoSlow", function()
	movement:CreateToggle({ Name = "NoSlow", CurrentValue = S.FEATURES.noslow,
		Callback = function(v) S.FEATURES.noslow = v end }, "noslow")
end)
safe("toggle Fly", function()
	movement:CreateToggle({ Name = "Fly", CurrentValue = S.FEATURES.fly,
		Callback = function(v) S.FEATURES.fly = v; printOn("Fly", v) end }, "fly")
end)
safe("slider Fly speed", function()
	movement:CreateSlider({ Name = "Fly speed", Range = { 0.05, 0.5 }, Increment = 0.05, CurrentValue = S.VALUES.flySpeed,
		Callback = function(v) S.VALUES.flySpeed = v end }, "flyspeed")
end)
safe("toggle Noclip", function()
	movement:CreateToggle({ Name = "Noclip", CurrentValue = S.FEATURES.noclip,
		Callback = function(v) S.FEATURES.noclip = v; printOn("Noclip", v) end }, "noclip")
end)
safe("toggle Spider", function()
	movement:CreateToggle({ Name = "Spider", CurrentValue = S.FEATURES.spider,
		Callback = function(v) S.FEATURES.spider = v; printOn("Spider", v) end }, "spider")
end)

-- Render -----------------------------------------------------------------
safe("toggle ESP", function()
	render:CreateToggle({ Name = "ESP", CurrentValue = S.FEATURES.esp,
		Callback = function(v) S.FEATURES.esp = v end }, "esp")
end)
safe("toggle Nametags", function()
	render:CreateToggle({ Name = "Nametags", CurrentValue = S.FEATURES.nametags,
		Callback = function(v) S.FEATURES.nametags = v end }, "nametags")
end)
safe("toggle Watermark", function()
	render:CreateToggle({ Name = "Watermark", CurrentValue = S.FEATURES.watermark,
		Callback = function(v)
			S.FEATURES.watermark = v
			S.setWmVisible(v)
		end }, "watermark")
end)

-- Client -----------------------------------------------------------------
safe("bind Aura", function()
	client:CreateBind({ Name = "Aura bind", CurrentBind = S.BINDS.aura.Name, HoldToInteract = false,
		Callback = function() end,
		OnChangedCallback = function(k) S.BINDS.aura = k end }, "bindaura")
end)
safe("bind Speed", function()
	client:CreateBind({ Name = "Speed bind", CurrentBind = S.BINDS.speed.Name, HoldToInteract = false,
		Callback = function() end,
		OnChangedCallback = function(k) S.BINDS.speed = k end }, "bindspeed")
end)
safe("bind Kill", function()
	client:CreateBind({ Name = "Kill bind", CurrentBind = S.BINDS.kill.Name, HoldToInteract = false,
		Callback = function() end,
		OnChangedCallback = function(k) S.BINDS.kill = k end }, "bindkill")
end)
safe("button Unload", function()
	client:CreateButton({ Name = "Unload", Callback = function()
		S.unload()
	end })
end)
safe("theme section", function()
	client:BuildThemeSection()
end)

pcall(function()
	Luna:LoadAutoloadConfig()
end)

print("[Astolfo] gui built")
