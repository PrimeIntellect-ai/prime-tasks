Null values in columns of type `boolean` are returned as `false`
### Specifications

* Client Version: 1.29.0
* InfluxDB Version: 2.0.7
* Platform: Linux


### Code sample to reproduce problem

```javascript
import { InfluxDB } from '@influxdata/influxdb-client'

const token = '### enter token ###';
const queryApi = new InfluxDB({url: 'http://localhost:8086', token}).getQueryApi('Org');

queryApi.queryRows(
        `import "experimental/array"

        array.from(rows: [
                {_measurement: "m0", _field: "f0", _value: true, _time: 2020-01-01T00:00:00Z,},
                {_measurement: "m0", _field: "f1", _value: true, _time: 2020-01-01T00:00:00Z,},
                {_measurement: "m0", _field: "f0", _value: true,  _time: 2020-01-01T01:00:00Z,},
                // no entry for f1 at 01:00:00 -> _value will be set to null by pivot()
        ])
                |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")`,
        {
                next: (row, tableMeta) => {
                        console.log(`At ${tableMeta.get(row, '_time')} f0 is ${tableMeta.get(row, 'f0')} and f1 is ${tableMeta.get(row, 'f1')}`);
                },
                error: e => console.log(e),
                complete: () => {},
        }
);

```


### Expected behavior

```
At 2020-01-01T00:00:00Z f0 is true and f1 is true
At 2020-01-01T01:00:00Z f0 is true and f1 is null
```

### Actual behavior

```
At 2020-01-01T00:00:00Z f0 is true and f1 is true
At 2020-01-01T01:00:00Z f0 is true and f1 is false
```

### Additional info

[HIDDEN]
