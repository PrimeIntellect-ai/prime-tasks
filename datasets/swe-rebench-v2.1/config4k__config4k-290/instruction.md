`java.time.temporal.TemporalAmount` should be serializable
Inspired by a great work of @alexmihailov in https://github.com/Kotlin/kotlinx.serialization/pull/2133

### Additional contract requirements

- Support serialization and deserialization of `java.time.temporal.TemporalAmount` values in Config4k’s HOCON format when used with Kotlin serialization contextual support, such as with `@Contextual`.
- Support `java.time.Duration` and `java.time.Period` values. Encode them as HOCON temporal amount strings and decode those strings to the corresponding concrete type while preserving the amount (for example, `5 m` as a duration and `1 y` or `10 mo` as a period).
