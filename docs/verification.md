# Verification — 2026-10-24

Target: **Test Place 1**, place ID **85947721356138**. Changes were scoped to `ReplicatedStorage.Chronocast` and `ServerStorage.ChronocastTests`.

## Tooling and sync

- Argon CLI **2.0.29**, installed with `nix profile install nixpkgs#argon`.
- Existing Creator Store Argon plugin used; a redundant newly downloaded local plugin was moved out of Studio's plugin directory to avoid duplicate loading.
- Session `chronocast` listens on **127.0.0.1:8000**. `argon exec 'return game.PlaceId' chronocast` succeeded.
- Read back all **28** synced LuaSourceContainers in Edit mode; normalized-source checksums matched all local files with no mismatches.
- `argon build chronocast.project.json -o /tmp/chronocast-check.rbxlx` passed.
- All source/test Lua files compiled with Nix's `luau-compile` **0.738**. This is a syntax check, not Roblox type analysis.

## Live tests

Ran in a real Studio **Server** DataModel during Play:

```lua
require(game.ServerStorage.ChronocastTests.Run)()
```

Final result after code-review fixes: **3/3 suites passed**, then **3/3 passed again in the same Play session**:

- `Geometry.spec`: all twelve query/target pairs, nine overlap target-surface/normal checks, generated local collision, cylinder axial bounds, ray direction/inside behavior, oriented boxes, capsule endpoint tangency and Line/custom path checks.
- `History.spec`: immutable data, independent configuration, ring-buffer replacement/eviction, out-of-order timestamp rejection, historical collision and Context caching.
- `Scheduling.spec`: shared Roblox server-time epoch, automatic Heartbeat capture, historical hit after movement, future-only collision replacement, metadata values, validation and untracking/destruction.

An initial run exposed `table.freeze` rejecting a Context with a protected metatable. Removed metatable protection and froze the metatable and handle instead; restarted Play before the passing run.

After the simplification cleanup (unused copy helper, mode parameter and Context import), restarted Play and ran the full suite once more: **3/3 passed**. Final Edit readback again matched all 28 local sources with no extra scripts. Argon build and syntax compilation also passed after cleanup.

Read console PASS output. The client DataModel's `Chronocast:GetServerTime()` differed from `Workspace:GetServerTimeNow()` by zero in the live check. Existing asset-type mismatch warnings came from the test place and were not Chronocast test failures. Returned Studio to Edit mode. No test fixture is intentionally retained in Workspace. Requested ordinary Ctrl+S as a checkpoint; no Publish command used.

## Scope limits

Paths are discrete pose samples, not continuous sweeps. Queries still enumerate all tracked timelines; temporal spatial indexing is not implemented. This run does not establish production-scale performance or real multiplayer weapon integration.
