How to set `metric_version` on `inputs.prometheus`
I am looking for how to set `metric_version=2` on the generated config for `inputs.prometheus`.

Current output:
```
[[inputs.prometheus]]
  urls = ["http://127.0.0.1:8086/metrics"]
  interval = "30s"
```

Desired output:
```
[[inputs.prometheus]]
  urls = ["http://127.0.0.1:8086/metrics"]
  interval = "30s"
  metric_version=2
```

### Additional contract requirements

- If the `telegraf.influxdata.com/metric-version` annotation has value `2`, the generated `inputs.prometheus` TOML must include the numeric setting `metric_version = 2`. If that annotation is present with a nonnumeric value, config generation must return an error.
