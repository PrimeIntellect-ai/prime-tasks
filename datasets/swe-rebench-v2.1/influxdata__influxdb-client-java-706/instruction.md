IPv6 hosts are not supported
https://github.com/influxdata/influxdb-client-java/blob/886eb8840b4d72fdb9973801ba4cd6e1d6fa1306/client/src/main/java/com/influxdb/client/InfluxDBClientOptions.java#L697

The InfluxDBClientOptions.ParsedUrl constructor strips the square brackets off IPv6 addresses, rendering urls containing them invalid. E.g. `http://[2001:db8:3333:4444:5555:6666:7777:8888]:8086/` becomes `http://2001:db8:3333:4444:5555:6666:7777:8888:8086/`.

See how okhttp3 HttpUrl.Builder.toString() handles IPv6 addresses.

### Additional contract requirements

- For URLs of the form `http://<host>:9999/api/v2/query?orgID=my-org` with any of these malformed IPv6 hosts—`[:1]`, `[:::1]`, `[2001:db8:0000:1]`, `[2001:db8:00000::1]`, `[2001:db8:0000:::1]`, `[:0000::1]`, or `[:::0000::1]`—building options must throw `com.influxdb.exceptions.InfluxException` with the exact message `Unable to parse connection string ` followed by the original URL.
