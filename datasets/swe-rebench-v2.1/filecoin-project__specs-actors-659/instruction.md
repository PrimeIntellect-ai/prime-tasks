Power actor EnrollCronEvent doesn't handle enrolments for events in the past
The `EnrollCronEvent` method does no validation of the epoch for which an event is enrolled. If it's at or prior to the recorded `LastEpochTick` then the event will never be executed and will remain in state forever. Events are stored in a HAMT keyed by epoch, which does not support ordered traversal.

A simple solution might be to require the registered epoch to be after the current epoch. However at present it is possible for a registration to be in "the past" when there is a long chain halt (greater than a proving period) from the miner actor, which steps its proving period marker forward one period at a time via cron events.

A workaround-style solution might be to change how the miner actor registers for proving period callbacks, ensuring registrations are always in the future, even when catching up from a long halt. This seems brittle, though, and easy to accidentally introduce a new case that might require an in-the-past registration (I haven't audited other cases yet).

Another possible path out is switching all such callback mechanisms to use chain height (#408), which will never have gaps or null rounds.

I think a robust solution would be to [HIDDEN]. The event callbacks must then be robust to being called at an epoch later than they registered, but that's necessary anyway to handle empty tipsets.

### Additional contract requirements

- `EnrollCronEvent` must reject an event epoch less than zero by aborting with `exitcode.ErrIllegalArgument`. When the requested epoch is `-2`, the abort message must contain `epoch -2 cannot be less than zero`.
- Enrolling a non-negative event epoch must remain valid even when it is earlier than the current epoch or a previously processed cron tick; a later cron tick must dispatch that event.
- When one cron tick dispatches multiple due events, their callbacks must be dispatched in increasing event-epoch order.
- A cron callback must tolerate invocation at an epoch later than the epoch for which it was registered.
