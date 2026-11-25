# Lag-compensated hitscan

When a player fires, they're aiming at where other players appear on **their** screen. Because of replication and interpolation, that's slightly in the past. Checking the shot against where everyone is *now* makes good shots miss. This example checks it against where everyone *was* when the shooter saw them.

## Files

| File | Put it in | Does |
|---|---|---|
| `ShotValidator.lua` | ServerScriptService, next to `Server` | Rewinds, clamps, validates untrusted input, and casts. Pure logic with no networking; covered by `tests/LagCompensation.spec.lua`. |
| `Server.server.lua` | ServerScriptService | Tracks every character with per-limb collision, receives shots, applies damage (headshots do more). |
| `Client.client.lua` | StarterPlayerScripts | On click, fires from your head toward the mouse and sends `workspace:GetServerTimeNow()`. |

Chronocast itself goes in ReplicatedStorage.

## How a shot is judged

1. **Shape check.** Origin and direction must be finite `Vector3`s, and the time a finite number. Anything else is rejected as `MalformedShot`.
2. **Rewind.** `viewTime = clientTime - InterpolationDelay`, clamped to `[now - MaxRewind, now]`. A client claiming its shot is very old gets at most `MaxRewind` of help, and a client clock that runs ahead by more than `MaxClockLead` is rejected.
3. **Plausibility.** The reported origin must be within `MaxOriginError` studs of where the shooter's character was at `viewTime`.
4. **Cast.** A ray of length `Range` at `viewTime`, excluding the shooter. The result's `Name` is the limb that was hit.

`Validate` returns the hit and `viewTime`, or `nil` and one of these reasons: `Miss`, `MalformedShot`, `ClientTimeInFuture`, `OriginMismatch` or `UnknownShooter`. Log the reasons while tuning.

## Tuning

| Option | Default | Notes |
|---|---|---|
| `InterpolationDelay` | `0.1` | How far behind other players appear on clients. Measure in your game; it depends on replication settings. |
| `MaxRewind` | `0.3` | The most lag you'll compensate for. Larger is fairer to high-ping players and worse for the players being shot ("shot around a corner"). |
| `MaxClockLead` | `0.05` | Tolerance for client clocks slightly ahead of the server. |
| `MaxOriginError` | `6` | Slack between the reported muzzle and the recorded character root. |
| `Range` | `500` | Weapon range in studs. Keep it finite: bounded rays use the spatial index. |

`HistoryDuration` on each timeline must cover `MaxRewind` (the default of 5 s does). The server script also rate-limits shots per player. A real game should add its own checks, such as ammo and line of sight from the camera.
