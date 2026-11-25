-- Chronocast v2 - Type Definitions
--
-- Exported Luau types for the public API. Fields match what functions actually
-- accept and return; access them as Chronocast.Types.<Name> via require.

export type CollisionShape = "Box" | "Sphere" | "Capsule" | "Compound"

-- Offsets are local to the transform the timeline's adapter returns.
-- Compound children are primitive shapes local to the compound's Offset.
export type CollisionDef = {
	Shape: CollisionShape,
	Offset: CFrame,
	Size: Vector3?, -- Box
	Radius: number?, -- Sphere, Capsule
	Height: number?, -- Capsule: distance between cap centers
	Name: string?, -- reported as the hit's Name
	Children: { CollisionDef }?, -- Compound
}

export type Timeline = {
	Id: string,
	GetState: (self: Timeline, time: number) -> State?,
	GetSnapshots: (self: Timeline) -> { Snapshot },
	SetCollision: (self: Timeline, collision: (CollisionDef | CollisionProvider)?) -> (),
	Destroy: (self: Timeline) -> (),
	isDestroyed: (self: Timeline) -> boolean,
}

-- Sampled on every capture; the result is validated, copied and frozen into the snapshot.
export type CollisionProvider = (timeline: Timeline, time: number) -> CollisionDef?

export type Adapter = {
	GetTransform: (self: Adapter, timeline: Timeline, time: number) -> CFrame,
	GetVelocity: ((self: Adapter, timeline: Timeline, time: number) -> Vector3?)?,
	GetAngularVelocity: ((self: Adapter, timeline: Timeline, time: number) -> Vector3?)?,
	Metadata: { [string]: any }?,
}

export type TimelineConfig = {
	Id: string, -- stable, unique, nonempty
	Adapter: Adapter?, -- required unless Instance inference is used
	Instance: Instance?, -- BasePart, or Model with a stable PrimaryPart
	Collision: (CollisionDef | CollisionProvider)?,
	SnapshotInterval: number?, -- seconds between captures (not Hz)
	SnapshotRate: number?, -- deprecated alias of SnapshotInterval
	HistoryDuration: number?, -- seconds of history retained
	Metadata: { [string]: any }?, -- values, or providers (timeline, time) -> value
	Interpolation: { [string]: any }?,
}

export type Snapshot = {
	Time: number,
	Transform: CFrame,
	Velocity: Vector3?,
	AngularVelocity: Vector3?,
	Metadata: { [string]: any },
	Collision: CollisionDef?,
}

export type State = {
	Time: number,
	Transform: { CFrame: CFrame, Position: Vector3, Rotation: CFrame },
	Motion: { Velocity: Vector3?, AngularVelocity: Vector3? },
	Metadata: { [string]: any },
	Collision: CollisionDef?, -- definition recorded by the preceding snapshot
}

export type Path = {
	Sample: (self: Path, alpha: number) -> CFrame,
	Intervals: number?, -- Intervals + 1 poses are tested, including both endpoints
	Samples: number?, -- deprecated alias of Intervals
}

export type QueryShape = "Ray" | "Sphere" | "Box" | "Capsule"

-- With a Path, each pose supplies Origin/CFrame, so they may be omitted.
export type RayParams = { Origin: Vector3, Direction: Vector3, MaxDistance: number? }
export type SphereParams = { Origin: Vector3, Radius: number }
export type BoxParams = { Origin: Vector3?, CFrame: CFrame?, Size: Vector3 }
export type CapsuleParams = { Origin: Vector3?, CFrame: CFrame?, Radius: number, Height: number }

export type QueryParams = {
	Shape: QueryShape,
	Parameters: RayParams | SphereParams | BoxParams | CapsuleParams,
	Path: Path?, -- discrete pose sampling, not a continuous sweep
	Filter: ((timeline: Timeline) -> boolean)?,
}

-- Context:Cast. Distance is exact ray travel, or approximate chord travel along a Path.
export type CastResult = {
	Timeline: Timeline,
	Distance: number,
	Position: Vector3, -- on the target surface
	Normal: Vector3, -- outward target normal
	Name: string?, -- name of the hit collision shape (e.g. a character limb)
}

-- Context:Overlap. A representative contact, not a full manifold; no Distance.
export type OverlapResult = {
	Timeline: Timeline,
	Position: Vector3,
	Normal: Vector3,
	Name: string?,
}

-- Deprecated Context:Query / Chronocast:Query result.
export type QueryResult = {
	Hit: boolean,
	Timeline: Timeline?,
	Distance: number?, -- ray/path travel, or a shape-pair separation metric for static volumes
	Position: Vector3?,
	Normal: Vector3?,
	Name: string?,
}

export type Context = {
	Time: number,
	GetState: (self: Context, timeline: Timeline) -> State?,
	GetCollision: (self: Context, timeline: Timeline) -> CollisionDef?,
	GetSnapshots: (self: Context, timeline: Timeline) -> { Snapshot },
	Cast: (self: Context, params: QueryParams) -> CastResult?,
	Overlap: (self: Context, params: QueryParams) -> { OverlapResult },
	Query: (self: Context, params: QueryParams) -> QueryResult,
	Destroy: (self: Context) -> (),
	IsDestroyed: (self: Context) -> boolean,
}

return {}
