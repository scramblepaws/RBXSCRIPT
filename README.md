# RBXSCRIPT

Roblox executor scripts for the voxel pit game (`Ugc`). No Humanoids — players are
`MCBody` models, and combat is resolved by the game's own controller from your replicated
pose + real mouse clicks (probing showed clicking fires **no** remote).

## Files

- `aimbot.lua` — head-CFrame aim + auto-click. Keys: **F** aim+click, **G** speed boost,
  **L** kill switch (fully unloads). Exposes `getgenv().Aim`.
- `recon.lua` — decompiles the game's client scripts to `RBXDUMP/` (AdvancedDecompilerV3,
  Konstant API fallback) and writes a remote index. Run this to read the real mechanics.
- `remote_probe.lua` — hooks every remote, logs each one the first time it fires.
- `game_dumps_analyzer.lua` — continuous dump of remotes / hierarchy / player state.
- `loadstring_loader.lua` — pulls a script from this repo's raw URL.

## Gotchas

- The game has **no Humanoids**. Players are `MCBody <userId>` models.
- `workspace.MCBody` (exact name) is a **template rig** — every part is at 0,0,0. Never aim
  or measure distance against it; that was why aim "did nothing" and distances read 0.
- Your own avatar is `MCBody <yourUserId>` and must be excluded from target lists.
- Clicking fires **no remote** — the game resolves hits server-side from your replicated
  pose, so damage comes from real mouse clicks (`mouse1click` / `VirtualInputManager`).

## Loading

```lua
loadstring(game:HttpGet("<raw url of the .lua>"))()
```
