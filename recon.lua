-- Recon — decompile the game's client code so we can read the real mechanics.
-- Uses AdvancedDecompilerV3 (w-a-e / infyiff backup) + the executor's getscriptbytecode.
-- Writes every script it can to `RBXDUMP/<path>.lua`, prints a summary, and lists remotes.
--
-- Run in the executor:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/scramblepaws/RBXSCRIPT/master/recon.lua"))()

local DECOMPILER_URL = "https://raw.githubusercontent.com/infyiff/backup/main/AdvancedDecompilerV3/init.lua"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local OUT = "RBXDUMP"

local function say(...)
	print("[recon]", ...)
end

--------------------------------------------------------------------
-- Filesystem (executor)
--------------------------------------------------------------------

local hasFs = type(writefile) == "function" and type(isfolder) == "function" and type(makefolder) == "function"

local function ensureDir(path)
	if not hasFs then
		return false
	end
	if isfolder(path) then
		return true
	end
	local ok = makefolder(path)
	return ok or isfolder(path)
end

local function save(relPath, contents)
	if not hasFs then
		return false
	end
	local path = OUT .. "/" .. relPath
	local dir = path:match("^(.*)/[^/]+$")
	if dir then
		local acc = ""
		for part in dir:gmatch("[^/]+") do
			acc = acc == "" and part or (acc .. "/" .. part)
			ensureDir(acc)
		end
	end
	local ok = pcall(writefile, path, contents)
	return ok
end

local function sanitize(name)
	return (name:gsub("[^%w%-%._ ]", "_"))
end

--------------------------------------------------------------------
-- Decompiler
--------------------------------------------------------------------

local decompile
do
	local ok, res = pcall(function()
		return loadstring(game:HttpGet(DECOMPILER_URL, true))()
	end)
	if ok and res ~= nil then
		decompile = _ENV.decompile
		say("decompiler loaded")
	else
		say("decompiler FAILED to load: " .. tostring(res))
	end
	if type(decompile) ~= "function" then
		say("decompile() unavailable (getscriptbytecode=" .. tostring(type(getscriptbytecode) == "function") .. ")")
		decompile = nil
	end
end

-- fallback: Konstant's server-side decompiler (needs executor `request`)
local requestFn = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local KONSTANT_URL = "http://api.plusgiant5.com/konstant/decompile"

local function konstantDecompile(inst)
	if type(requestFn) ~= "function" or type(getscriptbytecode) ~= "function" then
		return nil
	end
	local ok, bc = pcall(getscriptbytecode, inst)
	if not ok or type(bc) ~= "string" or #bc == 0 then
		return nil
	end
	task.wait(0.55) -- their API is rate limited to 2/s
	local ok2, res = pcall(requestFn, {
		Url = KONSTANT_URL,
		Method = "POST",
		Body = bc,
		Headers = { ["Content-Type"] = "text/plain" },
	})
	if ok2 and res and res.StatusCode == 200 and type(res.Body) == "string" and #res.Body > 0 then
		return res.Body
	end
	return nil
end

--------------------------------------------------------------------
-- Walk the client's scripts
--------------------------------------------------------------------

local scripts = {}

local function addScript(inst, path)
	scripts[#scripts + 1] = { inst = inst, path = path }
end

local function walk(inst, path, depth)
	if depth > 8 then
		return
	end
	for _, c in ipairs(inst:GetChildren()) do
		local childPath = path .. "/" .. sanitize(c.Name)
		if c:IsA("LocalScript") or c:IsA("ModuleScript") or (c:IsA("Script") and c.RunContext == Enum.RunContext.Client) then
			addScript(c, childPath)
		end
		if c:IsA("Folder") or c:IsA("Model") or c:IsA("Actor") then
			walk(c, childPath, depth + 1)
		end
	end
end

local player = Players.LocalPlayer
if player then
	walk(player:FindFirstChild("PlayerScripts") or player, "PlayerScripts", 0)
end
walk(ReplicatedFirst, "ReplicatedFirst", 0)
walk(ReplicatedStorage, "ReplicatedStorage", 0)

--------------------------------------------------------------------
-- Dump
--------------------------------------------------------------------

local okCount, failCount, lines = 0, 0, 0
local index = {}

for _, entry in ipairs(scripts) do
	local src
	if decompile then
		local ok, res = pcall(decompile, entry.inst)
		if ok and type(res) == "string" and #res > 0 then
			src = res
		end
	end
	if not src then
		local viaKonstant = konstantDecompile(entry.inst)
		if viaKonstant then
			src = "-- [via konstant api]\n" .. viaKonstant
		end
	end
	if src then
		okCount = okCount + 1
		local n = select(2, src:gsub("\n", "")) + 1
		lines = lines + n
		save(entry.path .. ".lua", "-- " .. entry.inst:GetFullName() .. "\n" .. src)
		index[#index + 1] = string.format("%s (%d lines)", entry.path, n)
	else
		failCount = failCount + 1
		index[#index + 1] = string.format("%s (FAILED)", entry.path)
	end
end

--------------------------------------------------------------------
-- Remotes index
--------------------------------------------------------------------

local remoteLines = {}
local function collectRemotes(node, path, depth)
	if depth > 6 then
		return
	end
	for _, c in ipairs(node:GetChildren()) do
		local childPath = path .. "." .. c.Name
		if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") or c:IsA("UnreliableRemoteEvent") then
			remoteLines[#remoteLines + 1] = childPath .. "  [" .. c.ClassName .. "]"
		end
		pcall(collectRemotes, c, childPath, depth + 1)
	end
end
pcall(collectRemotes, ReplicatedStorage, "ReplicatedStorage", 0)

--------------------------------------------------------------------
-- Report
--------------------------------------------------------------------

say(string.format("scripts found: %d  decompiled: %d  failed: %d  total lines: %d", #scripts, okCount, failCount, lines))
say("filesystem: " .. (hasFs and "yes (wrote " .. OUT .. "/)" or "NO — paste this output to the dev instead"))
for _, l in ipairs(index) do
	say("  " .. l)
end
say(string.format("remotes: %d", #remoteLines))
save("_remotes.txt", table.concat(remoteLines, "\n"))
save("_index.txt", table.concat(index, "\n"))

if not hasFs then
	say("---- remotes ----")
	for _, l in ipairs(remoteLines) do
		say(l)
	end
end

-- quick self-check: a known wall of the dump
assert(#scripts > 0, "[recon] found no scripts — walk roots are wrong for this game")
