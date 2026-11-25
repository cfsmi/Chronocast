-- Chronocast v2 - History Module
--
-- Manages snapshot storage and interpolation for timelines.

local History = {}

History.RingBuffer = require(script.RingBuffer)
History.Interpolation = require(script.Interpolation)

return History