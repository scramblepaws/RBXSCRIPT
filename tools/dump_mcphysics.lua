-- DumpMCPhysics — the first dump skipped MCPhysics' children (they live under a
-- ModuleScript, not a Folder). Backfill them to RBXDUMP_SRC.
-- Run: loadstring(game:HttpGet("<raw url>"))()

local dec = rawget((getgenv and getgenv()) or _G, "decompile")
if type(dec) ~= "function" or type(writefile) ~= "function" then
	print("[dump] needs decompile + writefile")
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local node = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("MCPhysics")
if not node then
	print("[dump] MCPhysics not found")
	return
end

pcall(function()
	makefolder("RBXDUMP_SRC")
end)

for _, c in ipairs(node:GetChildren()) do
	if c:IsA("ModuleScript") then
		local ok, src = pcall(dec, c)
		if ok and type(src) == "string" and #src > 0 then
			pcall(writefile, "RBXDUMP_SRC/Shared_MCPhysics_" .. c.Name .. ".lua", src)
			print("  ok  Shared_MCPhysics_" .. c.Name .. ".lua (" .. #src .. " chars)")
		else
			print("  FAIL " .. c.Name .. ": " .. tostring(src))
		end
	end
end

print("[dump] done")
