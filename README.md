# RBXSCRIPT

Roblox executor scripts for the voxel pit game (`Ugc`). No Humanoids — players are
`MCBody` models, and combat is resolved by the game's own controller from your replicated
pose + real mouse clicks (probing showed clicking fires **no** remote).

## Files

- `aimbot.lua` — head-CFrame aim + auto-click. Toggle with **F**. Exposes `getgenv().Aim`
  (`AimPart`, `AimAt`, `findTarget`, `findHead`, `click`).
- `remote_probe.lua` — hooks every remote, logs each one the first time it fires. Use to
  re-verify how a game mechanic reaches the server. Toggle dump with **F**.
- `game_dumps_analyzer.lua` — continuous dump of remotes / hierarchy / player state to
  `game dumps/<Game>_<PlaceId>/`. Console controls: `GameDumpsExport()`, `GameDumpsStatus()`, `GameDumpsStop()`.
- `loadstring_loader.lua` — pulls a script from this repo's raw URL.

## Loading

```lua
loadstring(game:HttpGet("<raw url of the .lua>"))()
```
