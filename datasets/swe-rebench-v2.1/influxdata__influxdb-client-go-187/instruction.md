2.0: go.mod invalid
After latest release go.mod seems invalid:

```
❯ go get github.com/influxdata/influxdb-client-go@v2.0.0
go get github.com/influxdata/influxdb-client-go@v2.0.0: github.com/influxdata/influxdb-client-go@v2.0.0: invalid version: module contains a go.mod file, so major version must be compatible: should be v0 or v1, not v2
```

[HIDDEN]

### Additional contract requirements

- The module must be resolvable at version `v2.0.0` without Go reporting an invalid major-version/module-path error.
