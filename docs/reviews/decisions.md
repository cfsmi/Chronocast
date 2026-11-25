# Review decisions

## Code review — applied

All three concrete findings were addressed: cylinders now use conservative oriented boxes without axial protrusion; new out-of-order ring timestamps are rejected; swapped overlap handlers return target-side contacts. The normal ambiguity was resolved explicitly: overlap contacts use outward target normals, with deterministic handling of degenerate configurations. Regression tests cover these contracts. No continuous-sweep or nearby-only performance claim is made.

## Architecture — recommended next iteration, not implemented

I agree with the report's main proposal: distinguish **Cast** (one first hit, travel distance) from **Overlap** (a deterministic collection of intersecting targets, no misleading travel distance). Current `Query` ranks overlap candidates using different geometric metrics across shape pairs. A generic `Distance` cannot honestly describe all of them.

Recommended order:

1. Specify results, ordering, input validation, and out-of-history behavior; add real exported Luau types rather than comment-only annotations.
2. Introduce `Context:Cast` and `Context:Overlap`, retaining `Context:Query` during a versioned migration. Preserve current miss behavior for compatibility until a deliberate breaking release; do not silently change `{ Hit = false }` into nil.
3. Rename the capture interval to `SnapshotInterval` (or introduce explicit `SnapshotHz` with conversion), while accepting the existing `SnapshotRate` name as a temporary alias. Define `Samples` as intervals, or rename it to avoid the current `Samples + 1` pose ambiguity.

Two caveats to the report: a fixed context time plus cached states does not yet pin registry membership or preserve uncached snapshots indefinitely as buffers roll. Define context expiry/retention before promising a permanent historical view. Also, wiring the dormant grid using only current positions would miss historical targets; spatial filtering must conservatively cover history and shape bounds.

I would defer query builders, additional managers, new primitives, and continuous sweeps until these contracts are settled. No proposed Cast/Overlap redesign was silently applied in this change.

## Simplification — small cleanup applied, larger changes deferred

Removed the unused `Utils.deepCopy`, the unused copy-helper mode parameter, and an unused Context import. Kept the nontrivial geometry explanations and ownership comments. I rejected speculative config-copy modes: they would add branching before measurement shows a benefit. Multiple copy/freeze boundaries remain until allocation profiling and mutation-isolation tests justify consolidation. Dormant spatial-index options are a deliberate follow-up, not something to delete incidentally.
