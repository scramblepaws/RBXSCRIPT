-- ReadDump — show what recon.lua actually saved, and whether the live scripts have bytecode.
-- Run: loadstring(game:HttpGet("<raw url>"))()
-- Paste everything it prints.

local CAP = 1800 -- chars of each file to print

local CANDIDATES = {
	"PlayerScripts/Client",
	"ReplicatedStorage/Shared/Net/Inputs",
	"ReplicatedStorage/Shared/Net/MoveAuthority",
	"ReplicatedStorage/Shared/Net/Simulation",
	"ReplicatedStorage/Shared/MCPhysics",
	"ReplicatedStorage/Shared/AimAssist",
	"ReplicatedStorage/Shared/LagComp",
	"ReplicatedStorage/Shared/SnapshotBuffer",
}

local function looksLikeCode(s)
	return s:find("function") or s:find("local ") or s:find("return")
end

local function findLive(path)
	local node = game
	for part in path:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

print("[readdump] files: " .. tostring(isfolder ~= nil and isfolder("RBXDUMP") or false))

for _, path in ipairs(CANDIDATES) do
	print("==== " .. path .. " ====")
	local ok, content = pcall(readfile, "RBXDUMP/" .. path .. ".lua")
	if ok and type(content) == "string" then
		print(string.format("saved: %d bytes, code-ish=%s", #content, tostring(looksLikeCode(content) ~= nil)))
		print(content:sub(1, CAP))
		if #content > CAP then
			print("... [truncated, " .. #content .. " bytes total]")
		end
	else
		print("saved file unreadable: " .. tostring(content))
	end

	local inst = findLive(path)
	if inst then
		local okBc, bc = pcall(getscriptbytecode, inst)
		print(string.format("live bytecode: %s (%s bytes)",
			tostring(okBc and type(bc) == "string"),
			tostring(okBc and type(bc) == "string" and #bc or "n/a")))
	else
		print("live instance not found")
	end
end

print("[readdump] done")
