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

local Window = Luna:CreateWindow({
	Name = "astolfo",
	Subtitle = "v6",
	LogoID = "82795327169782",
	LoadingEnabled = true,
	LoadingTitle = "astolfo",
	LoadingSubtitle = "pastel pvp client",
	ConfigSettings = { RootFolder = nil, ConfigFolder = "Astolfo" },
	KeySystem = false,
})
S.Window = Window
Window.Bind = Enum.KeyCode.RightShift

function S.buildGui() end

local function printOn(name, v)
	print("[Astolfo] " .. name .. " " .. (v and "ON" or "OFF"))
end

-- Combat -----------------------------------------------------------------
local combat = Window:CreateTab({ Name = "Combat", Icon = "sports_martial_arts", ImageSource = "Material", ShowTitle = false })
combat:CreateSection("KillAura")
combat:CreateToggle({ Name = "KillAura", CurrentValue = S.FEATURES.aura,
	Callback = function(v) S.FEATURES.aura = v; printOn("KillAura", v) end }, "aura")
combat:CreateSlider({ Name = "CPS", Range = { 1, 20 }, Increment = 1, CurrentValue = S.VALUES.cps,
	Callback = function(v) S.VALUES.cps = v end }, "cps")
combat:CreateSlider({ Name = "Range", Range = { 10, 60 }, Increment = 5, CurrentValue = S.VALUES.range,
	Callback = function(v) S.VALUES.range = v end }, "range")
combat:CreateSlider({ Name = "Reach", Range = { 2.5, 4 }, Increment = 0.1, CurrentValue = S.VALUES.reach,
	Callback = function(v)
		S.VALUES.reach = v
		S.applyReach(v)
	end }, "reach")
combat:CreateSlider({ Name = "AttackDist", Range = { 2.5, 4.5 }, Increment = 0.1, CurrentValue = S.VALUES.attackDist,
	Callback = function(v) S.VALUES.attackDist = v end }, "attackdist")
combat:CreateSlider({ Name = "FOV (360 = off)", Range = { 30, 360 }, Increment = 10, CurrentValue = S.VALUES.fov,
	Callback = function(v) S.VALUES.fov = v end }, "fov")
combat:CreateDropdown({ Name = "Targets", Options = { "All", "Players", "Bots" }, CurrentOption = { S.VALUES.targets }, MultipleOptions = false,
	Callback = function(v) S.VALUES.targets = v end }, "targets")
combat:CreateDropdown({ Name = "Aim", Options = { "Instant", "Smooth" }, CurrentOption = { S.VALUES.aimMode }, MultipleOptions = false,
	Callback = function(v) S.VALUES.aimMode = v end }, "aim")
combat:CreateToggle({ Name = "Glow target", CurrentValue = S.FEATURES.glow,
	Callback = function(v) S.FEATURES.glow = v end }, "glow")
combat:CreateToggle({ Name = "TargetStrafe", CurrentValue = S.FEATURES.strafe,
	Callback = function(v) S.FEATURES.strafe = v; printOn("TargetStrafe", v) end }, "strafe")

combat:CreateSection("Velocity")
combat:CreateToggle({ Name = "Velocity", CurrentValue = S.FEATURES.velocity,
	Callback = function(v) S.FEATURES.velocity = v; printOn("Velocity", v) end }, "velocity")
combat:CreateSlider({ Name = "KB keep %", Range = { 0, 100 }, Increment = 10, CurrentValue = S.VALUES.kbKeep,
	Callback = function(v) S.VALUES.kbKeep = v end }, "kbkeep")

combat:CreateSection("AutoClicker")
combat:CreateToggle({ Name = "AutoClicker", CurrentValue = S.FEATURES.autoclick,
	Callback = function(v) S.FEATURES.autoclick = v; printOn("AutoClicker", v) end }, "autoclick")

-- Movement ---------------------------------------------------------------
local movement = Window:CreateTab({ Name = "Movement", Icon = "directions_run", ImageSource = "Material", ShowTitle = false })
movement:CreateToggle({ Name = "Speed", CurrentValue = S.FEATURES.speed,
	Callback = function(v)
		S.FEATURES.speed = v
		print("[Astolfo] Speed " .. (v and ("ON x" .. S.VALUES.speed) or "OFF"))
	end }, "speed")
movement:CreateSlider({ Name = "Multiplier", Range = { 1, 5 }, Increment = 0.5, CurrentValue = S.VALUES.speed,
	Callback = function(v) S.VALUES.speed = v end }, "speedmult")
movement:CreateToggle({ Name = "Bhop", CurrentValue = S.FEATURES.bhop,
	Callback = function(v) S.FEATURES.bhop = v end }, "bhop")
movement:CreateToggle({ Name = "NoSlow", CurrentValue = S.FEATURES.noslow,
	Callback = function(v) S.FEATURES.noslow = v end }, "noslow")
movement:CreateToggle({ Name = "Fly", CurrentValue = S.FEATURES.fly,
	Callback = function(v) S.FEATURES.fly = v; printOn("Fly", v) end }, "fly")
movement:CreateSlider({ Name = "Fly speed", Range = { 0.05, 0.5 }, Increment = 0.05, CurrentValue = S.VALUES.flySpeed,
	Callback = function(v) S.VALUES.flySpeed = v end }, "flyspeed")
movement:CreateToggle({ Name = "Noclip", CurrentValue = S.FEATURES.noclip,
	Callback = function(v) S.FEATURES.noclip = v; printOn("Noclip", v) end }, "noclip")
movement:CreateToggle({ Name = "Spider", CurrentValue = S.FEATURES.spider,
	Callback = function(v) S.FEATURES.spider = v; printOn("Spider", v) end }, "spider")

-- Render -----------------------------------------------------------------
local render = Window:CreateTab({ Name = "Render", Icon = "visibility", ImageSource = "Material", ShowTitle = false })
render:CreateToggle({ Name = "ESP", CurrentValue = S.FEATURES.esp,
	Callback = function(v) S.FEATURES.esp = v end }, "esp")
render:CreateToggle({ Name = "Nametags", CurrentValue = S.FEATURES.nametags,
	Callback = function(v) S.FEATURES.nametags = v end }, "nametags")
render:CreateToggle({ Name = "Watermark", CurrentValue = S.FEATURES.watermark,
	Callback = function(v)
		S.FEATURES.watermark = v
		S.setWmVisible(v)
	end }, "watermark")

-- Client -----------------------------------------------------------------
local client = Window:CreateTab({ Name = "Client", Icon = "settings", ImageSource = "Material", ShowTitle = false })
client:CreateBind({ Name = "Aura bind", CurrentBind = S.BINDS.aura.Name, HoldToInteract = false,
	Callback = function() end,
	OnChangedCallback = function(k) S.BINDS.aura = k end }, "bindaura")
client:CreateBind({ Name = "Speed bind", CurrentBind = S.BINDS.speed.Name, HoldToInteract = false,
	Callback = function() end,
	OnChangedCallback = function(k) S.BINDS.speed = k end }, "bindspeed")
client:CreateBind({ Name = "Kill bind", CurrentBind = S.BINDS.kill.Name, HoldToInteract = false,
	Callback = function() end,
	OnChangedCallback = function(k) S.BINDS.kill = k end }, "bindkill")
client:CreateButton({ Name = "Unload", Callback = function()
	S.unload()
end })
client:BuildThemeSection()

pcall(function()
	Luna:LoadAutoloadConfig()
end)
