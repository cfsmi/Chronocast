# Code Review: Automatic capture and historical collision

Static review of current source against `prd.md`, `README.md`, and tests. No Studio actions or source edits were performed. Main orchestrator reported that the three suites passed in a real Test Place 1 server Play session, Luau syntax compilation passed, and Argon build passed; those results were not independently rerun here.

## Verified findings

### [P2] Cylinder conversion produced an overlong capsule — RESOLVED; live rerun passed

Original location: `src/ReplicatedStorage/Chronocast/Collision/FromPart.lua:23-30`. Storing cylinder axial length as capsule cap-center separation made a `(4,2,2)` cylinder collision extend to 6 studs axially. The source now uses a conservative oriented Box instead, and `tests/Geometry.spec.lua:94-103` checks exact axial contact at the generated bound. This avoids false axial protrusion; the box remains a conservative approximation of the round cylinder cross-section.

### [P2] Ring buffer accepted out-of-order timestamps — RESOLVED; live rerun passed

Original location: `src/ReplicatedStorage/Chronocast/History/RingBuffer.lua:62-82`. Inserting `10,12,11` kept insertion order and broke bracketing: a query at exactly `12` eventually chose `11` as the `before` snapshot and `12` as `after`, so interpolation could return preceding state/collision instead of the exact-time sample. (The prior report's claim that query 11.5 reversed the bracket was incorrect; exact 12 exposes the defect.) The source now rejects new older timestamps unless replacing an existing timestamp. `tests/History.spec.lua:63-64` checks out-of-order rejection and evicted timestamp index cleanup.

### [P2] Box/Sphere overlap reported contact on the query box — RESOLVED; live rerun passed

Original location: `src/ReplicatedStorage/Chronocast/Query/init.lua:274-279`.

The Box-query/Sphere-target handler swaps the inputs to `sphereBox`, treating the query box as the target box. Consequently `Position` comes from the query box's closest point, not the historical target sphere. For a query box centered at x=0 with size 2 and target sphere centered at x=1.5 with radius 1, the hit position is x=1 (query-box face), while the target sphere's contact surface toward the box is x=0.5. Consumers treating `Position` as a target contact point get a point on the wrong shape. The query computes valid overlap, so existing “Hit” coverage does not catch this.

**Fix:** Implement Sphere-vs-Box geometry with the target sphere as the contact reference (or explicitly document that `Position` is not consistently a target contact point); add an overlapping-but-not-tangent geometry assertion.

## Hypotheses / needs contract clarification

- **Overlap `Normal` orientation is inconsistent if it means outward target normal** (`src/ReplicatedStorage/Chronocast/Query/init.lua:108-125`, `188-222`, `274-279`): sphere/sphere and capsule/sphere compute target-center minus query-center, which points into the target at the returned target-side surface point; sphere/box instead points from target box toward query center. Box/box similarly orients its SAT normal query-to-target. Ray normals are outward target normals. This inconsistency is visible in the code, but PRD/README never define normal orientation for overlap queries, so whether it is a defect is a contract ambiguity. Recommend one contract (e.g. always outward from target at `Position`) and normalize all handlers, then test normal direction across all 12 pairs.

## Verification

The review agent inspected source only and did not independently run Studio/builds.

Orchestrator follow-up: corrected Box/Sphere and Box/Capsule target-side contacts, standardized outward target normals, and documented representative (not manifold) overlap contacts. Added target surface/normal assertions for all nine overlap shape pairs. All three suites passed twice in the same real Studio server Play session after these changes, including the cylinder and timestamp-order regression tests. Client clock delta against `Workspace:GetServerTimeNow()` was zero. See `docs/verification.md`.

The normal-contract question above is now resolved in README and tests. Broader result ranking/Distance semantics remain an interface-review topic.