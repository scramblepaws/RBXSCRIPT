-- patches — live game-constant patches (reach, anti-cheat flag), restored on unload
local S = getgenv().Astolfo

function S.applyReach(v)
	if not S.physics or not S.physics.Combat then
		return
	end
	S.physics.Combat.REACH = v
end

function S.patchGame()
	local changed = {}
	if S.physics then
		if S.physics.Combat and S.physics.Combat.REACH then
			S.orig.combatReach = S.physics.Combat.REACH
			S.applyReach(S.VALUES.reach)
			changed[#changed + 1] = "Combat.REACH " .. S.orig.combatReach .. "->" .. S.VALUES.reach
		end
		if S.physics.Blocks and S.physics.Blocks.REACH then
			S.orig.blockReach = S.physics.Blocks.REACH
			S.physics.Blocks.REACH = 4.5
			changed[#changed + 1] = "Blocks.REACH " .. S.orig.blockReach .. "->4.5"
		end
	end
	local config = S.requireShared("Config")
	if config and config.AntiCheat then
		S.orig.acEnabled = config.AntiCheat.Enabled
		config.AntiCheat.Enabled = false
		changed[#changed + 1] = "AntiCheat.Enabled " .. tostring(S.orig.acEnabled) .. "->false"
	end
	return #changed > 0 and table.concat(changed, ", ") or "nothing patched"
end

S.patchResult = S.patchGame()

function S.restorePatches()
	local p = S.requireShared("MCPhysics")
	if p then
		if S.orig.combatReach and p.Combat then
			p.Combat.REACH = S.orig.combatReach
		end
		if S.orig.blockReach and p.Blocks then
			p.Blocks.REACH = S.orig.blockReach
		end
	end
	if S.orig.acEnabled ~= nil then
		local config = S.requireShared("Config")
		if config and config.AntiCheat then
			config.AntiCheat.Enabled = S.orig.acEnabled
		end
	end
end
