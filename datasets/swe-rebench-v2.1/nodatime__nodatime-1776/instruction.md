Effective Instant serialization/deserialization
I've faced a problem with effective serialization and deserialization `Instant` for MessagePack. `Instant` has a precision of nanoseconds. The best safe way for serialization is getting nanoseconds amount (and create an instance of `Instant` from nanoseconds for deserialization). But the minimum accessible unit of time from Instant is ticks (`.ToUnixTimeTicks()`).
I can't use ticks, because value can be truncated (`Instant.MaxValue` for example)

Now there are a few terrible ways to serialize/deserialize an Instant:
- with InstantPattern (as string with format pattern). It's a slowest way, and uses a lot of memory
- with code smells way: getting `Duration` with `Instant.MinValue - instant` for serialization, and getting `Instant` with 'Instant.Add(Instant.MinValue, duration)' for deserialization
- with dirty hacks for getting access to private fields: Reflection, Linq Expressions

[HIDDEN]

Do you have any thoughts about this?

### Additional contract requirements

- `Instant` must provide a public instance method `ToUnixTimeSecondsAndNanoseconds()` that returns a tuple `(long seconds, int nanoseconds)`.
- `seconds` is the same value that `ToUnixTimeSeconds()` returns for the instant. `nanoseconds` is the remaining sub-second part, counted forward from that second, so it is always between 0 and 999,999,999 inclusive, including for instants before the Unix epoch.
- Passing the two returned values to `Instant.FromUnixTimeSeconds` and then `PlusNanoseconds` must reproduce the original instant exactly. This must hold for values that are not a whole number of ticks, and for `Instant.MinValue` and `Instant.MaxValue`.
