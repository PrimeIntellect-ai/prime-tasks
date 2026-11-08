Add support for SINTERCARD command
I didn't see `SinterCard` command(https://redis.io/commands/sintercard) in `go-redis`, Is there any particular reason for not supporting this?  if not, I'd happy to make contributions. I've finished coding and unit test.

### Additional contract requirements

- The client must expose the SINTERCARD command as `SInterCard(ctx context.Context, limit int64, keys ...string) *IntCmd`, where `keys` are the set keys to intersect.
- The command's `Val()` must return the number of members common to all the given sets, as an `int64`.
- A positive `limit` caps the returned count: the result is at most `limit`.
- A `limit` of `0` requests the full intersection cardinality, with no cap.
