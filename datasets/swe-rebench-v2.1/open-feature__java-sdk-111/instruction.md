Change package name?
On the Sept 29 community call, an attendee suggested we remove "java" from the package names in the SDK (their argument was "java" is implied). I see their point, though I also don't think it's needed.

Basically: `dev.openfeature.javasdk` would become: `dev.openfeature.sdk`.

I'm just bringing this up because "now is the time" before we start marking things as stable. Mostly interested in @justinabrahms 's opinion on this one.

**UPDATE: We will likely do this at 1.0**

### Additional contract requirements

- For this task, change the SDK’s Java package hierarchy from `dev.openfeature.javasdk` to `dev.openfeature.sdk` now; this is a required change, not a proposal deferred to a future 1.0 release.
