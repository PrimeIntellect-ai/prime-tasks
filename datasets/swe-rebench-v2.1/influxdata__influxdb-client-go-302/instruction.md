`(*api.QueryTableResult).Record().Table()` doesn't return the right value when compared with `(*api.QueryTableResult).Record().String()`
<!--

Thank you for reporting a bug.

* Please add a :+1: or comment on a similar existing bug report instead of opening a new one.
    * https://github.com/influxdata/influxdb-client-go/issues?utf8=%E2%9C%93&q=is%3Aissue+is%3Aopen+is%3Aclosed+sort%3Aupdated-desc+label%3Abug+
* Please check whether the bug can be reproduced with the latest release.
* The fastest way to fix a bug is to open a Pull Request.
    * https://github.com/influxdata/influxdb-client-go/pulls

-->

__Steps to reproduce:__
List the minimal actions needed to reproduce the behavior.

Writer:
```go
var client influxdb.Client
writeAPI := client.WriteAPIBlocking(org, "public")
point := influxdb2.NewPoint(
  "DEBUG",
  map[string]string{
	"request_id":  "900f983d-d90d-4bee-8cc7-db0dbddc1381",
	"application": "core",
	"environment": "UNSET",
  },
  map[string]interface{}{
	"language": "Hello",
	"message":  "61207461736b206a7573742073746172746564",
	"body":     "7b2248656c6c6f223a2248656c6c6f227d",
  },
  time.Now(),
)
err = writeAPI.WritePoint(ctx, point)
```

Query for reader:
```
from(bucket: "public")
|> range(start: 0)
|> sort(columns: ["_time"])
|> group(columns: ["request_id", "_time"])
|> filter(fn: (r) => r["_measurement"] == "DEBUG")
|> yield()
```

Then:
```go
rows, err := queryAPI.Query(ctx, query)

for rows.Next() {
  fmt.Println(rows.Record().Table())
  fmt.Println(rows.Record().String())
}
```

__Expected behavior:__
`Table()` should reflect the `table` value from the `String()` method. So, suppose I got this from `rows.Record().String()`:
```
environment:UNSET,request_id:900f983d-d90d-4bee-8cc7-db0dbddc1381,_start:1970-01-01 00:00:00 +0000 UTC,_stop:2022-01-13 15:11:04.5872657 +0000 UTC,_time:2022-01-13 14:34:00.5584149 +0000 UTC,_field:message,application:worker,result:_result,table:2,_value:61207461736b206a7573742073746172746564,_measurement:DEBUG
```

Then `rows.Record().Table()` should returns 2 as the value on the `table` key is 2, right?

__Actual behavior:__
Instead, it returns 0.
```
0
environment:UNSET,request_id:900f983d-d90d-4bee-8cc7-db0dbddc1381,_start:1970-01-01 00:00:00 +0000 UTC,_stop:2022-01-13 15:11:04.5872657 +0000 UTC,_time:2022-01-13 14:34:00.5584149 +0000 UTC,_field:message,application:worker,result:_result,table:2,_value:61207461736b206a7573742073746172746564,_measurement:DEBUG
```

__Specifications:__
 - Client Version: 2.6.0
 - InfluxDB Version: Docker 2.1.1-alpine
 - Platform: Debian 10
