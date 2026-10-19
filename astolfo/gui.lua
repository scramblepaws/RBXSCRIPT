-- gui — Rayfield menu (pastel Astolfo look via the built-in theme)
local S = getgenv().Astolfo

local ok, Rayfield = pcall(function()
	return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not ok or type(Rayfield) ~= "table" then
	print("[Astolfo] Rayfield failed to load — menu unavailable")
	return
end
S.Rayfield = Rayfield

local Window = Rayfield:CreateWindow({
	Name = "astolfo",
	LoadingTitle = "astolfo",
	LoadingSubtitle = "pastel pvp client",
	ConfigurationSaving = { Enabled = false },
	KeySystem = false,
})
S.Window = Window

function S.buildGui() end -- menu is built here at load time

local function printOn(name, v)
	print("[Astolfo] " .. name .. " " .. (v and "ON" or "OFF"))
end

-- Combat -----------------------------------------------------------------
local combat = Window:CreateTab("Combat", "4483362458")

combat:CreateSection("KillAura")
combat:CreateToggle({ Name = "KillAura", CurrentValue = S.FEATURES.aura, Flag = "aura",
	Callback = function(v) S.FEATURES.aura = v; printOn("KillAura", v) end })
combat:CreateSlider({ Name = "CPS", Range = { 1, 20 }, Increment = 1, CurrentValue = S.VALUES.cps,
	Callback = function(v) S.VALUES.cps = v end })
combat:CreateSlider({ Name = "Range", Range = { 10, 60 }, Increment = 5, CurrentValue = S.VALUES.range,
	Callback = function(v) S.VALUES.range = v end })
combat:CreateSlider({ Name = "Reach", Range = { 2.5, 4 }, Increment = 0.1, CurrentValue = S.VALUES.reach,
	Callback = function(v)
		S.VALUES.reach = v
		S.applyReach(v)
	end })
combat:CreateSlider({ Name = "AttackDist", Range = { 2.5, 4.5 }, Increment = 0.1, CurrentValue = S.VALUES.attackDist,
	Callback = function(v) S.VALUES.attackDist = v end })
combat:CreateSlider({ Name = "FOV (360 = off)", Range = { 30, 360 }, Increment = 10, CurrentValue = S.VALUES.fov,
	Callback = function(v) S.VALUES.fov = v end })
combat:CreateDropdown({ Name = "Targets", Options = { "All", "Players", "Bots" }, CurrentOption = S.VALUES.targets,
	Callback = function(v) S.VALUES.targets = v end })
combat:CreateDropdown({ Name = "Aim", Options = { "Instant", "Smooth" }, CurrentOption = S.VALUES.aimMode,
	Callback = function(v) S.VALUES.aimMode = v end })
combat:CreateToggle({ Name = "Glow target", CurrentValue = S.FEATURES.glow, Flag = "glow",
	Callback = function(v) S.FEATURES.glow = v end })
combat:CreateToggle({ Name = "TargetStrafe", CurrentValue = S.FEATURES.strafe, Flag = "strafe",
	Callback = function(v) S.FEATURES.strafe = v; printOn("TargetStrafe", v) end })

combat:CreateSection("Velocity")
combat:CreateToggle({ Name = "Velocity", CurrentValue = S.FEATURES.velocity, Flag = "velocity",
	Callback = function(v) S.FEATURES.velocity = v; printOn("Velocity", v) end })
combat:CreateSlider({ Name = "KB keep %", Range = { 0, 100 }, Increment = 10, CurrentValue = S.VALUES.kbKeep,
	Callback = function(v) S.VALUES.kbKeep = v end })

combat:CreateSection("AutoClicker")
combat:CreateToggle({ Name = "AutoClicker", CurrentValue = S.FEATURES.autoclick, Flag = "autoclick",
	Callback = function(v) S.FEATURES.autoclick = v; printOn("AutoClicker", v) end })

-- Movement ---------------------------------------------------------------
local movement = Window:CreateTab("Movement", "3259050989")
movement:CreateToggle({ Name = "Speed", CurrentValue = S.FEATURES.speed, Flag = "speed",
	Callback = function(v)
		S.FEATURES.speed = v
		print("[Astolfo] Speed " .. (v and ("ON x" .. S.VALUES.speed) or "OFF"))
	end })
movement:CreateSlider({ Name = "Multiplier", Range = { 1, 5 }, Increment = 0.5, CurrentValue = S.VALUES.speed,
	Callback = function(v) S.VALUES.speed = v end })
movement:CreateToggle({ Name = "Bhop", CurrentValue = S.FEATURES.bhop, Flag = "bhop",
	Callback = function(v) S.FEATURES.bhop = v end })
movement:CreateToggle({ Name = "NoSlow", CurrentValue = S.FEATURES.noslow, Flag = "noslow",
	Callback = function(v) S.FEATURES.noslow = v end })

-- Render -----------------------------------------------------------------
local render = Window:CreateTab("Render", "3602733521")
render:CreateToggle({ Name = "ESP", CurrentValue = S.FEATURES.esp, Flag = "esp",
	Callback = function(v) S.FEATURES.esp = v end })
render:CreateToggle({ Name = "Nametags", CurrentValue = S.FEATURES.nametags, Flag = "nametags",
	Callback = function(v) S.FEATURES.nametags = v end })
render:CreateToggle({ Name = "Watermark", CurrentValue = S.FEATURES.watermark, Flag = "watermark",
	Callback = function(v)
		S.FEATURES.watermark = v
		S.setWmVisible(v)
	end })

-- Client -----------------------------------------------------------------
local client = Window:CreateTab("Client", "80503127983237")
client:CreateKeybind({ Name = "Aura bind", CurrentKeybind = S.BINDS.aura.Name, HoldToInteract = false,
	Callback = function(k) S.BINDS.aura = k end })
client:CreateKeybind({ Name = "Speed bind", CurrentKeybind = S.BINDS.speed.Name, HoldToInteract = false,
	Callback = function(k) S.BINDS.speed = k end })
client:CreateKeybind({ Name = "Kill bind", CurrentKeybind = S.BINDS.kill.Name, HoldToInteract = false,
	Callback = function(k) S.BINDS.kill = k end })
client:CreateButton({ Name = "Unload", Callback = function()
	S.unload()
end })
