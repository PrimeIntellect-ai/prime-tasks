term field reader stats out of sync when advancing backwards
The scorch implementation of `TermFieldReader` `Advance()` has special handling for the case when it is advancing backwards.  [HIDDEN]  This works, but the stats tracking is not handled correctly, and this leads to the `TotTermSearchersStarted` and `TotTermSearchersFinished` stats to get out of sync.

### Additional contract requirements

- After a `TermFieldReader` is advanced backwards and closed, its accounting must not leave `TotTermSearchersStarted` and `TotTermSearchersFinished` out of sync.
