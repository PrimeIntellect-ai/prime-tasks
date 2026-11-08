Market Actor: Should we be able to Terminate the same deals twice
Currently, it is possible to mark the same deal as terminated twice by calling `OnMinerSectorsTerminate` twice with the same dealID. The `SlashEpoch` on the deal will be the last `CurrentEpoch` it was called at.

Is this the expected behaviour ?

@anorth

### Additional contract requirements

- Terminating a deal that has already been terminated must not change its `SlashEpoch`. The `SlashEpoch` recorded by the first termination is preserved; a repeated termination must never move it to a later epoch. A repeated termination may either be ignored (leaving the deal's `SlashEpoch` unchanged) or rejected as an illegal duplicate.
- When a single `OnMinerSectorsTerminate` call includes both already-terminated deals and not-yet-terminated deals, the not-yet-terminated deals are still terminated at the current epoch.
