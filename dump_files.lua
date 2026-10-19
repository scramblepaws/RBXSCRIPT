-- DumpFiles — decompile the whole Shared tree + the client controller and WRITE
-- each module to RBXDUMP_SRC/*.lua in the executor workspace (no console spam).
-- Run: loadstring(game:HttpGet("<raw url>"))()
-- Afterwards: find the RBXDUMP_SRC folder in your executor's workspace folder and
-- tell me its path (or it gets auto-discovered).

local dec = rawget((getgenv and getgenv()) or _G, "decompile")
if type(dec) ~= "function" then
	print("[dump] no decompile global (fresh session?)")
	return
end
if type(writefile) ~= "function" then
	print("[dump] no writefile — cannot export to disk")
	return
end

pcall(function()
	makefolder("RBXDUMP_SRC")
end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local written, failed = 0, {}

local function save(inst, outName)
	if not inst then
		failed[#failed + 1] = outName
		return
	end
	local ok, src = pcall(dec, inst)
	if ok and type(src) == "string" and #src > 0 then
		local ok2 = pcall(writefile, "RBXDUMP_SRC/" .. outName .. ".lua", src)
		if ok2 then
			written = written + 1
			print("  ok  " .. outName .. ".lua (" .. #src .. " chars)")
		else
			failed[#failed + 1] = outName .. "(write)"
		end
	else
		failed[#failed + 1] = outName
		print("  FAIL " .. outName .. ": " .. tostring(src))
	end
end

-- client controller + its children
local ps = player:WaitForChild("PlayerScripts", 8)
if ps:FindFirstChild("Client") then
	save(ps.Client, "Client_main")
	for _, c in ipairs(ps.Client:GetChildren()) do
		if c:IsA("ModuleScript") or c:IsA("LocalScript") then
			save(c, "Client_" .. c.Name)
		end
	end
else
	print("  no Client script in PlayerScripts")
end

-- the whole Shared tree
local shared = ReplicatedStorage:WaitForChild("Shared", 8)
local function walk(node, prefix)
	for _, c in ipairs(node:GetChildren()) do
		if c:IsA("ModuleScript") then
			save(c, prefix .. c.Name)
		elseif c:IsA("Folder") then
			walk(c, prefix .. c.Name .. "_")
		end
	end
end
walk(shared, "Shared_")

print("[dump] done — " .. written .. " files written to RBXDUMP_SRC/"
	.. (#failed > 0 and ("; failed: " .. table.concat(failed, ", ")) or ""))
