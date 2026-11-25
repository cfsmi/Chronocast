# Chronocast

A Roblox temporal query library. Track objects, retain immutable snapshots, and query reconstructed collision geometry without moving Workspace objects.

## Sync to Studio with Argon

Argon CLI 2.0.29 is installed through the user Nix profile. Studio already has the Creator Store Argon plugin (asset 11263738833); that installation is used to avoid duplicate plugins. A local-plugin fallback is saved at `~/.local/share/argon/Argon-2.0.23.rbxm`.

```sh
argon serve chronocast.project.json chronocast
# Or detach:
argon serve chronocast.project.json chronocast --async
argon stop --list
argon stop chronocast
```

Connect the Argon Studio plugin to **127.0.0.1:8000**, with **Server** initial-sync priority and **Two-Way Sync off**. The server only listens on loopback. The project permits **Test Place 1 (85947721356138)** and owns only:

- `ReplicatedStorage.Chronocast` ← `src/ReplicatedStorage/Chronocast`
- `ServerStorage.ChronocastTests` ← `tests`

Other place instances are preserved. Files are authoritative for these two subtrees; edit code locally. Save the place in Studio after syncing; syncing does not publish it.

## Use

Run in a server Script during Play:

```lua
local Chronocast = require(game.ReplicatedStorage.Chronocast)
local part = workspace.Target
local timeline = Chronocast:Track({
    Id = "Target",
    Instance = part,
    Collision = Chronocast.Collision.FromPart(part),
    SnapshotRate = 1 / 30, -- interval in seconds, not Hz
    HistoryDuration = 5,
})

local time = Chronocast:GetServerTime()
task.wait(0.1)
local context = Chronocast:CreateContext(time)
local state = context:GetState(timeline)
local hit = context:Query({
    Shape = "Ray",
    Parameters = {
        Origin = Vector3.new(0, 10, 0),
        Direction = Vector3.xAxis,
        MaxDistance = 100,
    },
})
context:Destroy()
Chronocast:Untrack("Target")
```

Tracking captures an initial snapshot, then one shared Heartbeat scheduler captures eligible timelines. No manual capture is needed. Missed physics frames are not fabricated. Capture failures warn and untrack the failing timeline without stopping healthy timelines.

For virtual objects, supply `Adapter.GetTransform(self, timeline, time)` returning a CFrame, with optional `GetVelocity` and `GetAngularVelocity`. Automatic inference supports BaseParts and Models with a stable PrimaryPart. Models use `GetPivot()` as their transform. IDs must be unique nonempty strings.

### Historical data

- Server time uses `Workspace:GetServerTimeNow()` in every environment.
- Snapshots, reconstructed states, and collision definitions are recursively immutable. Metadata accepts plain tables (including cycles), primitives, and supported immutable Roblox value types—not Instances, functions, or metatable-backed tables. Metadata providers are called during capture.
- Context state reconstruction is lazy and cached by timeline identity. Context time cannot be reassigned.
- `Timeline:SetCollision(definition)` applies to **future captures**; old snapshots retain their original collision definition.
- Queries outside recorded history use the nearest snapshot. Extrapolation is unsupported and rejected when enabled.
- Tracking, untracking, and direct `Timeline:Destroy()` manage scheduler membership. Destruction is idempotent.

### Collision and paths

Collision offsets are **local to the transform returned by the adapter**. `FromPart(part, referenceCFrame?)` defaults to `part.CFrame`; `FromModel(model, referenceCFrame?)` defaults to `model:GetPivot()`. Pass the adapter's reference frame when it differs. Custom collision constructors accept local offsets, not world transforms. Cylinders and mesh geometry use conservative oriented boxes; exact cylinder/mesh collision is not supported. Capsule `Height` is the distance between its sphere-cap centers; its total tip-to-tip height is `Height + 2 * Radius`.

Ray, Sphere, Box, and Capsule queries target Box, Sphere, and Capsule collision definitions. Overlap results return a representative point on the historical target surface and an outward target normal, not a full contact manifold. Coincident/contained configurations use a deterministic fallback. A ray beginning inside a target reports distance zero at its origin with a fallback normal. Paths sample geometry at discrete poses; they are **not continuous swept collision detection** and can miss targets between samples. `Samples` controls that tradeoff.

The existing spatial index is not yet connected to queries; candidate enumeration currently scans registered timelines. This is not yet the PRD's nearby-only performance model.

## Test

Start **Play**, switch the Command Bar to **Server**, then run:

```lua
require(game.ServerStorage.ChronocastTests.Run)()
```

The runner returns suite totals and details, and prints PASS/FAIL output. `Scheduling.spec` is a live Heartbeat integration test; geometry and history suites use deterministic fixtures. Stop and restart Play after code changes to clear Roblox's module cache. Tests are not automatically run on every Play.

Build the sync project without opening Studio:

```sh
argon build chronocast.project.json -o /tmp/chronocast.rbxlx
```

## Review and verification

- [Live verification](docs/verification.md)
- [Code review and resolutions](docs/reviews/code-review.md)
- [Proposed API architecture](docs/reviews/architecture-review.md)
- [Simplification review](docs/reviews/simplification-review.md)
- [Review decisions](docs/reviews/decisions.md)
