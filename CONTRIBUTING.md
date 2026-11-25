# Contributing to Chronocast

Thanks for helping. Bug reports with a minimal reproduction are as welcome as pull requests.

## Layout

| Path | Contents |
|---|---|
| `src/` | The library. `src/init.lua` is the `Chronocast` module. |
| `tests/` | Callable ModuleScript suites (`*.spec.lua`), the Studio runner `Run.lua`, and `Benchmark.lua`. |
| `examples/` | Usage examples. `LagCompensation/ShotValidator.lua` is covered by `tests/LagCompensation.spec.lua`. |
| `tools/headless.luau` | Runs the suites outside Studio under Lune. |
| `default.project.json` | The library only (what Wally and releases ship). |
| `test.project.json` | Library, tests and examples, for syncing into a test place. |
| `docs/design/` | Historical design notes. |

## Tools

Everything CI uses is pinned in `flake.nix` / `flake.lock`. With Nix installed:

```sh
nix develop    # shell with lune, stylua, selene, luau-lsp and rojo
```

Without Nix, install [Lune](https://github.com/lune-org/lune), [StyLua](https://github.com/JohnnyMorganz/StyLua), [Selene](https://github.com/Kampfkarren/selene), [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) and [Rojo](https://github.com/rojo-rbx/rojo) any way you like. Any recent version should work; the flake records the exact ones CI uses.

## Checks

CI runs these on every push and pull request. Please run them before opening a PR:

```sh
stylua src tests tools examples            # format (CI runs with --check)
selene src tests examples                  # lint
lune run tools/headless.luau               # tests, outside Studio
rojo build default.project.json -o Chronocast.rbxm
```

Type checking needs Roblox's API definitions:

```sh
curl -fsSL -o globalTypes.d.luau \
  "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$(luau-lsp --version)/scripts/globalTypes.d.luau"
rojo sourcemap test.project.json -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src tests examples
```

## Tests

### Headless (fast, no Studio)

```sh
lune run tools/headless.luau           # every suite except Scheduling.spec
lune run tools/headless.luau Query     # suites whose name contains "Query"
lune run tools/headless.luau --bench   # benchmark
```

The runner mirrors `src/`, `tests/` and `examples/` as Instances. It uses Lune's Roblox datatypes, with a stubbed clock and Heartbeat. Lune's `Vector3`/`CFrame` are much slower than Roblox's, so treat headless benchmark numbers as relative only.

### In Studio

Sync `test.project.json` into a test place (Rojo or Argon), start **Play**, switch the Command Bar to **Server**, then run:

```lua
require(game.ServerStorage.ChronocastTests.Run)()
```

This runs every suite, including `Scheduling.spec`, which exercises real Heartbeat capture. Stop and restart Play after code changes to clear Roblox's module cache. For Studio benchmark numbers, run `require(game.ServerStorage.ChronocastTests.Benchmark)()`.

### Writing tests

- A suite is a ModuleScript named `*.spec` that returns a function and raises on failure.
- Capture history with explicit timestamps (`timeline:captureSnapshot(base + i * dt)`, with `base` in the future) and don't yield, so Heartbeat can't interleave. Suites stay deterministic in both environments that way.
- Use `__`-prefixed timeline Ids and untrack them in cleanup, even on failure.
- Don't assume `Scheduling.spec`-style live timing in headless tests.

## Design principles

New features should fit as a timeline, a context, a query, a collision definition or a path (see [`docs/design/prd.md`](docs/design/prd.md)). Determinism, immutability of recorded history, and never modifying Workspace are hard constraints.

## Releases

1. Bump `version` in `wally.toml`.
2. Tag `vX.Y.Z` and push the tag. The release workflow checks that the tag matches `wally.toml`, runs the tests, and attaches `Chronocast.rbxm` to a GitHub release.
3. Publish to Wally manually: `wally login`, then `wally publish`.
