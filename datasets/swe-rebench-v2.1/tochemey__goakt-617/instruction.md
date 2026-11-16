feat: make passivation configurable per actor during creation
**Problem description**
The current implementation sets a global passivation for all actors created in the system. This can be a bottleneck when there are some actors that are supposed to be long lived while others can be passivated.

**Solution description**

- Allow during the creation of an actor to set the passivation time. When the passivation time is not set the default passivation mechanism will be used.
- One can also during the creation of the actor disable passivation for the given actor.

**Alternative solutions**
N/A

**Additional context**
N/A

This feature will help fix this feature request https://github.com/Tochemey/ego/issues/117 cc: @sdil

### Additional contract requirements

The per-actor settings are exposed as the `actors.WithPassivateAfter(after time.Duration)` and `actors.WithLongLived()` spawn options. `WithPassivateAfter` configures the actor to passivate after the supplied idle duration. `WithLongLived` disables automatic passivation for that actor. If neither option is supplied, the actor uses the actor system's default passivation mechanism.
