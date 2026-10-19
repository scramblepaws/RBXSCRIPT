-- Astolfo — entry point. Fetches the astolfo/ modules in order and starts.
-- Update REV whenever the modules change (pin to the commit sha).

local REV = "6cbb7b2"
local BASE = "https://raw.githubusercontent.com/scramblepaws/RBXSCRIPT/" .. REV .. "/astolfo/"

local S = getgenv and getgenv().Astolfo or nil
if type(S) ~= "table" or S.killed then
	S = {
		FEATURES = {
			aura = false, velocity = false, noslow = false, bhop = false,
			speed = false, glow = true, strafe = false, esp = true, watermark = true,
			autoclick = false, nametags = true, fly = false, noclip = false, spider = false,
		},
		VALUES = {
			cps = 10, range = 60, reach = 3.2, attackDist = 3.4,
			speed = 2.5, kbKeep = 0, targets = "All", aimMode = "Instant",
			fov = 360, flySpeed = 0.15,
		},
		BINDS = {
			aura = Enum.KeyCode.F, speed = Enum.KeyCode.G,
			kill = Enum.KeyCode.L,
		},
		WATERMARK_TEXT = "astolfo",
		orig = {},
		drawings = {},
	}
	if getgenv then
		getgenv().Astolfo = S
	end
end

S.Players = game:GetService("Players")
S.RunService = game:GetService("RunService")
S.UserInputService = game:GetService("UserInputService")
S.Workspace = game:GetService("Workspace")
S.ReplicatedStorage = game:GetService("ReplicatedStorage")
S.VirtualInputManager = game:GetService("VirtualInputManager")
S.player = S.Players.LocalPlayer
if not S.player then
	warn("[Astolfo] Needs to run as a client local script.")
	return
end

S.killed = false
S.target, S.targetDist, S.targetPos = nil, nil, nil
S.aimPoint = nil
S.lastClick = 0

local ORDER = {
	"lib", "targets", "patches", "features_combat", "features_movement",
	"esp", "hud", "gui", "main",
}

for _, name in ipairs(ORDER) do
	local ok, err = pcall(function()
		loadstring(game:HttpGet(BASE .. name .. ".lua", true))()
	end)
	print("[Astolfo] " .. name .. ": " .. (ok and "ok" or ("FAILED " .. tostring(err))))
end

if S.start then
	pcall(S.start)
end
