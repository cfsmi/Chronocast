Chronocast v2 - Product Requirements Document
Version: 2.0
 Status: Approved for Implementation
 Target Platform: Roblox (Luau)

Vision
Chronocast is a deterministic temporal query engine for Roblox.
Instead of rewinding the world, Chronocast reconstructs historical object states on demand and allows developers to query those reconstructed states through a unified API.
Its goal is to make historical world queries, lag compensation, replay systems, prediction utilities, and custom collision systems all use the same underlying temporal model.
Chronocast should feel less like a networking library and more like a database for time.

Design Philosophy
Every system in Chronocast should reinforce one idea:
Everything is a timeline.
Developers should never think about rewinding Workspace or replaying physics.
Instead, they ask questions about historical states.
Example:
local Context = Chronocast:CreateContext(Time)

local Result = Context:Query(...)
Chronocast reconstructs only what is necessary.
Nothing is physically rewound.
Nothing in Workspace is modified.

Core Principles
Deterministic
Given:
identical snapshot history
identical timestamp
identical query parameters
Chronocast must always produce the same result.

Lazy
No historical state is reconstructed until requested.
Creating a Context performs no reconstruction.
Objects are reconstructed only when accessed.

Immutable
Historical data never changes.
Contexts never mutate timelines.
Collision definitions are immutable.

Query Driven
Chronocast never reconstructs the entire world.
Only objects required for the active query are reconstructed.

Adapter First
Chronocast does not assume anything about how an object stores its data.
Developers are encouraged to provide custom adapters.
Automatic inference exists only as a convenience.

Non Goals
Chronocast is not:
Character controller
Replication framework
Movement framework
Physics replacement
Combat framework
Damage system
Replay editor
It provides temporal data.
Gameplay systems consume that data.

High Level Architecture
               Chronocast
                     │
      ┌──────────────┴──────────────┐
      │                             │
 Time Service                 Timeline Registry
                                     │
                              Timeline (per object)
                                     │
      ┌──────────────┬───────────────┴──────────────┐
      │              │                              │
 Snapshot Buffer   Adapter                   Collision Shapes
      │
      ▼
 Temporal Context
      │
      ▼
 Query Engine
      │
      ▼
 Query Results

Timeline
The Timeline is the fundamental object in Chronocast.
Everything revolves around timelines.
Tracking an object creates a Timeline.
local Timeline = Chronocast:Track({
    Id = "Player_1",

    Adapter = Adapter,

    Collision = Collision
})
A Timeline owns:
configuration
snapshot history
collision definition
metadata
adapter
Nothing else owns historical state.

Timeline Responsibilities
Capture snapshots
Store history
Reconstruct state
Expose snapshots
Manage collision data
Example:
Timeline:GetState(Time)

Timeline:GetSnapshots()

Timeline:SetCollision(Collision)

Timeline:Destroy()

Object Identity
Every tracked object requires a stable developer-provided identifier.
Id = "Player_12"
Chronocast never relies on Instance identity.
Instances may change during gameplay.
Timelines remain stable.

Adapters
Adapters describe how Chronocast retrieves temporal information.
Preferred approach:
{
    GetTransform = ...,
    GetVelocity = ...,
    Metadata = ...
}
Adapters provide temporal information only.
They do not own collision.

Auto Inference
If no adapter is supplied:
Chronocast attempts to infer:
Root transform
Linear velocity
Angular velocity
Inference is only valid if:
a stable root exists
transform source is unambiguous
Otherwise tracking fails.

Snapshot System
Each Timeline owns one ring buffer.
Characteristics:
fixed capacity
constant memory
overwrite oldest entries
Snapshots contain only the minimum required reconstruction data.
Minimum contract:
timestamp
transform
velocity (optional)

Snapshot Scheduling
Snapshots are automatically captured.
No manual snapshot API exists.
Snapshot rate is determined by:
default configuration
timeline overrides
deterministic performance scaling
Queries never influence snapshot creation.

State Model
Historical reconstruction returns a structured State.
State = {

    Time = number,

    Transform = {

        CFrame = CFrame,
        Position = Vector3,
        Rotation = CFrame

    },

    Motion = {

        Velocity = Vector3?,
        AngularVelocity = Vector3?

    },

    Metadata = {

    }

}
Chronocast never interprets Metadata.
It simply stores and reconstructs it.

Temporal Context
A Context represents one instant in time.
local Context =
    Chronocast:CreateContext(Time)
Contexts are immutable.
Contexts perform no work during creation.
Objects are reconstructed lazily.
The first request reconstructs an object.
Subsequent requests reuse cached reconstruction.
Context cache is local only.

Context API
Context:GetState(Timeline)

Context:GetSnapshots(Timeline)

Context:Query(Query)

Context:Destroy()
Contexts define time.
Queries inside a Context never specify timestamps.

Query System
Queries are pure functions.
They never modify history.
They never modify timelines.
They never modify Workspace.
General form:
Context:Query({

    Shape = ...,

    Parameters = ...,

    Path = ...

})

Shapes
Chronocast supports collision primitives.
Initial primitives:
Ray
Sphere
Box
Capsule
Future primitives may be added without changing the API.

Paths
Movement is separated from collision shape.
Paths define motion.
Shapes define collision volume.
Built in paths:
Chronocast.Path.Line()

Chronocast.Path.Bezier()

Chronocast.Path.Ballistic()

Chronocast.Path.Custom()
Every Path implements:
Path:Sample(alpha)
Nothing else is required.

Collision System
Collision is immutable.
Collision belongs to Timelines.
Collision is represented using collision shapes.
Not Roblox Parts.
Supported primitives:
Box
Sphere
Capsule
Each collision shape is stored in local space.
Example:
{

    Shape = Box,

    Offset = CFrame,

    Size = Vector3

}
Historical reconstruction transforms collision into world space.
Workspace is never modified.

Collision Generation
Chronocast provides utilities for generating collision definitions.
Example:
local Collision =
    Chronocast.Collision.FromModel(Model)
Developers may also construct collision manually.

Historical Reconstruction
Reconstruction uses:
snapshot interpolation
local collision transforms
cached Context state
Interpolation rules:
Position
Linear
Rotation
SLERP
Velocity
Sampled
Fallback:
exact snapshot
interpolation
nearest snapshot
No extrapolation by default.

Performance Model
Chronocast must satisfy:
No operation scales with total world size.
Query cost scales only with:
nearby timelines
collision complexity
query complexity

Spatial Filtering
Before reconstruction:
candidate timelines are selected using a spatial index.
Examples:
grid
BVH
octree
Implementation is internal.
Developers never interact with it.

Determinism
Chronocast guarantees deterministic output.
Given:
same timeline history
same timestamp
same query
Output is identical.
Execution order is irrelevant.

Public API
Chronocast:Track()

Chronocast:Untrack()

Chronocast:CreateContext()

Chronocast:Query()

Chronocast:GetServerTime()

Timeline API
Timeline:GetState()

Timeline:GetSnapshots()

Timeline:SetCollision()

Timeline:Destroy()

Context API
Context:GetState()

Context:GetSnapshots()

Context:Query()

Context:Destroy()

Collision API
Chronocast.Collision.FromModel()

Chronocast.Collision.FromPart()

Chronocast.Collision.Custom()

Path API
Chronocast.Path.Line()

Chronocast.Path.Bezier()

Chronocast.Path.Ballistic()

Chronocast.Path.Custom()

Configuration
Each Timeline may override:
snapshot rate
history duration
adapter
metadata providers
collision definition
Global defaults exist in Config.

Development Roadmap
Phase 1
Foundation
Types
Config
Enums
Utilities

Phase 2
Time System
server time
synchronization
timestamps

Phase 3
History
snapshots
ring buffer
interpolation

Phase 4
Timelines
tracking
adapters
history capture

Phase 5
Contexts
reconstruction
caching

Phase 6
Collision
generation
immutable collision shapes

Phase 7
Query Engine
ray
sphere
box
capsule

Phase 8
Paths
line
bezier
ballistic
custom

Phase 9
Performance
spatial index
adaptive snapshot scheduling
profiling

Success Criteria
Chronocast succeeds when:
Workspace is never rewound.
Historical state is reconstructed deterministically.
Queries require only relevant objects.
Timelines remain the single source of truth.
Every feature builds upon the same temporal model.
The API remains simple despite supporting complex temporal queries.

Guiding Principle
If a new feature cannot naturally be expressed as:
a Timeline,
a Context,
a Query,
a Collision definition, or
a Path,
then it likely does not belong in Chronocast’s core.

The engine should remain focused on one responsibility:
Reconstruct the past, then answer questions about it.

