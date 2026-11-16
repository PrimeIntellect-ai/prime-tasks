Accessing FluxRecord fields that are not returned by result result panic (flux `count()`, `pivot()`)
When executing [FluxRecord.Time()](https://github.com/influxdata/influxdb-client-go/blob/b73a2151a2b7ea9dda44b00bbb09564ef6c925b3/api/query/table.go#L155)  for query that does aggregation  Go panics ` interface conversion: interface {} is nil, not time.Time`

This is because these results do not have `_time` field in result and `nil` can not be cast to `time.Time`

https://github.com/influxdata/influxdb-client-go/blob/b73a2151a2b7ea9dda44b00bbb09564ef6c925b3/api/query/table.go#L156

There are other methods that could panic in same way `Start`/`Stop`/`Value` etc.   For example Flux function `pivot()` does not return `_value` column

I think allowing those methods to panic is little bit too much. Adding second field indicating if value exists - similarly as getting value from map  `val, ok := mymap[key]`  would have maybe less surprising results and not that punishing API.

Example query:
```
from(bucket:"data/autogen")
  |> range(start: 2021-03-22T16:05:20+02:00)
  |> filter(fn:(r) => r._measurement == "position" and (r._field =="latitude") and (r.type == "main"))
  |> count()
```

Result:
```
#datatype,string,long,dateTime:RFC3339,dateTime:RFC3339,string,string,string,long
#group,false,false,true,true,true,true,true,false
#default,_result,,,,,,,
,result,table,_start,_stop,_field,_measurement,type,_value
,,0,2021-03-22T14:05:20Z,2021-04-12T13:14:34.558380213Z,latitude,position,main,25997
```
