Nanosecond value in Point time field is stored in Long?
When creating points to write to influx using Java Instant:

```
        Instant stamp = Instant.now();
        Point point1 = Point.measurement("cpu")
                .time(stamp.getEpochSecond() * 1000000000 + stamp.getNano(), TimeUnit.NANOSECONDS)
                .addField("idle", 90L)
                .addField("system", 1L)
                .build();
```

From Java Instant documentation:
>The range of an instant requires the storage of a number larger than a long. To achieve this, the class stores a long representing epoch-seconds and an int representing nanosecond-of-second, which will always be between 0 and 999,999,999.

So the previous code may overflow the Long field for time. Maybe time would be better as BigInteger?

### Additional contract requirements

- Add a public method `Point.Builder.time(Number timeToSet, TimeUnit precisionToSet)` in `org.influxdb.dto.Point.Builder`. It accepts any numeric timestamp type (for example `Long`, `BigInteger`, `BigDecimal`), records the supplied precision, and returns the same `Builder` instance so that calls can be chained.
- Keep the public method `Point.Builder.time(Long timeToSet, TimeUnit precisionToSet)` in `org.influxdb.dto.Point.Builder`. It behaves like the `Number` overload.
- When a point's line protocol is generated with `Point.lineProtocol(TimeUnit precision)`, the timestamp supplied to `time(...)` is converted from the precision given there into the requested precision. A timestamp supplied as `BigInteger` or `BigDecimal` whose value exceeds the range of `long` must be preserved without overflow in the generated line protocol.
