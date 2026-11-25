# Architecture Review: Proposed Query Interface

Preserve Chronocast's central seams: timelines own history, contexts fix query time and cache reconstructed state, and queries leave `Workspace` untouched. Geometry/history fixes are now live-verified. The next iteration should clarify result semantics—especially `Distance` across ray, overlap, and sampled-path queries—not add managers or query builders.

## Suggested caller experience

Keep tracking adapter-first and use a single context as the explicit query-at-time seam:

```lua
local target = Chronocast:Track({
    Id = "Target", Instance = part,
    Collision = Chronocast.Collision.FromPart(part),
})
local at = Chronocast:CreateContext(Chronocast:GetServerTime() - 0.1)
local hit = at:Cast({ Shape = "Ray", Parameters = {
    Origin = origin, Direction = aim, MaxDistance = 200,
} })
if hit then
    print(hit.Timeline.Id, hit.Distance, hit.Position, hit.Normal)
end
at:Destroy()
```

This refines `Context:Query`, not its execution model. Make explicit context-time `Cast` and `Overlap` canonical; root `Chronocast:Query` hides time in its parameter table. Keep generic `Query({Shape, Parameters, Path})` as a compatibility entry point. Avoid duplicating Timeline/Context operations on the root.

## Contract to settle

Document Luau types for `TimelineConfig`, `Adapter`, `State`, query options, and results; `Types.lua` should match actual returned fields. Validate finite timestamps, IDs, shape parameters, and supported pairs at the public seam. Prefer explicit errors for malformed input, reserve `nil` for no hit, and make destroyed-context use consistently invalid. Keep capture failures isolated: warn and untrack the failing timeline. Adapters provide data, not history or collision.

A context is a stable historical view: creation does no reconstruction; first access caches immutable data. Timeline destruction releases history and unregisters it; context destruction releases its cache and invalidates further use. `SetCollision` affects subsequent captures only. Reject timestamps older than the newest snapshot (allow exact-time replacement). Context time, history, and per-snapshot collision never change.

Make **Cast** and **Overlap** distinct operations. `Cast` asks for the first target encountered along a directed query and returns one nearest hit; for a ray, `Distance` is exact ray travel. `Overlap` asks which historical targets intersect a volume and returns a deterministic collection (one representative contact per target, not a full manifold). Its result has no `Distance`: center separation/penetration heuristics are not travel and must not masquerade as it. Both may return `Position` on the target and outward `Normal`; the overlap point is representative, not a complete contact manifold. A sampled path is a Cast mode: return cumulative chord travel to the winning sampled pose/contact, explicitly approximate and dependent on `Samples`. Any other useful overlap metric should have a separately named and precisely defined field, not reuse `Distance`.

Paths are sampled, not continuous swept collision. Define the count precisely: today `Samples` means intervals, producing `Samples + 1` poses including both endpoints. Misses between poses are possible; cumulative chord travel is approximate.

## Priorities and migration

1. First, specify and test Cast versus Overlap contracts, `Distance` presence/meaning, deterministic ordering, validation, and destroyed-context behavior.
2. Add typed `Cast`/`Overlap` conveniences while preserving `Query` as a deprecated adapter for one migration window. Migrate old overlap `Distance` consumers to no field or a separately defined metric; do not preserve a misleading alias.
3. Correct `Types.lua` and examples to match actual results; validate public configuration and document defaults/overrides. Keep scheduler, ring buffer, interpolation, geometry dispatch, and spatial-index choice internal.

Defer builders, custom broadphase adapters, continuous sweeps, and extra primitives. First establish explicit time, typed intent, deterministic contacts, and clear lifecycle.