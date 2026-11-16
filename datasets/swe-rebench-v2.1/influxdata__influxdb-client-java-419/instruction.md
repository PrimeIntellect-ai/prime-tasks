Add getTime() to com.influxdb.client.write.Point
__Proposal:__
By adding a getter for the timestamp a developer can get more control on handling data points.
E.g. on handling the storing and retry of points in case of an not reachable InfluxDB.

__Current behavior:__
getter does not exists and value is private / class is final so there is no nice way to access the value

__Desired behavior:__
Calling point.getTime() to get the Timestamp

__Alternatives considered:__
Not declaring the Point class as final would allow to extend the Point class

__Use case:__
In my case collect values from a number of APIs into Points on Android. Points are can either go live to the InfluxDB and/or be cached into a local DB to be send when the connection to the DB is possible. Using the Timestamp to identify the points would be very helpful.

### Additional contract requirements

- `Point.getTime()` returns the timestamp as a `java.lang.Number`, holding the value in the units of the precision that was passed to `time(...)`. For example, a point set with `time(Instant.parse("2022-06-12T10:26:03.800123456Z"), WritePrecision.NS)` returns a value equal to `1655029563800123456`.
