Evaluate holding current day's key
Currently, a key that is still valid (rolling period + rolling period count covers the current time) causes a whole publish API request to fail.

As this has come up a couple of times, perhaps it is better to hold the still valid key until the end of the UTC day, but allow others to be sent out immediately.

/assign

### Additional contract requirements

- A still-valid key (one whose interval window extends past the current interval) must be accepted, not rejected. Its `CreatedAt` must be the end of that key's validity window: the start time of interval `IntervalNumber + IntervalCount`, truncated to the configured batch window.
- Keys in the same request that are no longer valid are stored with the normal batch `CreatedAt` (the batch time truncated to the batch window) and are sent immediately.
- When `releaseSameDayKeys` is true, still-valid keys are not embargoed: their `CreatedAt` is the normal batch time.
