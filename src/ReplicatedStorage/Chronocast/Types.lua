-- Chronocast v2 - Type Definitions
--
-- These are documentation-oriented type annotations for Luau.
-- They serve as the canonical type reference for the codebase.

--- @class Chronocast
--- @field Collision table
--- @field Path table
--- @field Config table
--- @field Types table

--- @class TimelineConfig
--- @field Id string - Stable developer-provided identifier
--- @field Adapter Adapter? - Adapter for temporal data; required unless Instance inference is used
--- @field Instance Instance? - BasePart or Model with a stable PrimaryPart for adapter inference
--- @field Collision CollisionDef? - Optional collision definition
--- @field SnapshotRate number? - Capture interval in seconds (not Hz)
--- @field HistoryDuration number? - Override default history duration
--- @field Metadata table? - Optional metadata providers

--- @class Adapter
--- @field GetTransform fun(timeline: table, time: number): CFrame?
--- @field GetVelocity fun(timeline: table, time: number): Vector3?
--- @field GetAngularVelocity fun(timeline: table, time: number): Vector3?
--- @field Metadata table?

--- @class Snapshot
--- @field Time number
--- @field Transform CFrame
--- @field Velocity Vector3?
--- @field AngularVelocity Vector3?
--- @field Metadata table?

--- @class State
--- @field Time number
--- @field Transform StateTransform
--- @field Motion StateMotion
--- @field Metadata table
--- @field Collision CollisionDef? - Definition recorded at capture time

--- @class StateTransform
--- @field CFrame CFrame
--- @field Position Vector3
--- @field Rotation CFrame

--- @class StateMotion
--- @field Velocity Vector3?
--- @field AngularVelocity Vector3?

--- @class Context
--- @field Time number

--- @class QueryParams
--- @field Shape string - "Ray" | "Sphere" | "Box" | "Capsule"
--- @field Parameters table - Shape-specific parameters
--- @field Path Path? - Optional discrete pose-sampling path, not a continuous sweep
--- @field Filter fun(timeline: table): boolean? - Optional candidate filter

--- @class CollisionDef
--- @field Shape string - "Box" | "Sphere" | "Capsule"
--- @field Offset CFrame
--- @field Size Vector3
--- @field Radius number? - For Sphere and Capsule
--- @field Height number? - For Capsule

--- @class Path
--- @field Sample fun(self: table, alpha: number): CFrame

--- @class QueryResult
--- @field Hit boolean
--- @field Position Vector3?
--- @field Normal Vector3? - Outward target normal; deterministic fallback for degenerate/inside cases
--- @field Timeline table?
--- @field Distance number?

--- @class RayParams
--- @field Origin Vector3
--- @field Direction Vector3
--- @field MaxDistance number?

--- @class SphereParams
--- @field Origin Vector3
--- @field Radius number

--- @class BoxParams
--- @field Origin Vector3
--- @field Size Vector3
--- @field CFrame CFrame?

--- @class CapsuleParams
--- @field Origin Vector3
--- @field Radius number
--- @field Height number
--- @field CFrame CFrame?

--- @class SpatialIndex
--- @field add fun(self: table, timeline: table)
--- @field remove fun(self: table, id: string)
--- @field query fun(self: table, region: table): { table }

local Types = {}

return Types