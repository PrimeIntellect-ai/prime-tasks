Client-side skipping of NaN values
A bit related to #537, but instead of validation I'd like to propose skipping NaNs to silence Telegraf/InfluxDB logs - they can't be reliably filtered, and some libraries (i.e. Kafka) use NaNs in their metric values.

Currently InfluxDB treats NaNs as invalid input, performs partial write and logs a warning. `InfluxDB#write` finishes with `InfluxDBException.UnableToParseException`.

I'd like to discuss having an option to silently drop invalid points during writes, or a clarification that clients shouldn't pass invalid values to points, so that logging in Apache Flink (apache/flink#8513) can be fixed in some way.

### Additional contract requirements

When serializing a point for a client-side write, NaN-valued fields are silently omitted while finite fields in that point are retained. If all fields are NaN, the point's line-protocol representation is empty, so no malformed fieldless point is emitted.
