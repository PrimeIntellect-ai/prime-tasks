Migrate gopsutil to v3 which supports go module
github.com/shirou/gopsutil have already supported go module in v3, we should follow up.

see https://github.com/shirou/gopsutil/blob/master/README.rst#v3-migration

### Additional contract requirements

- Use gopsutil v3 under its Go module path, `github.com/shirou/gopsutil/v3`, for the dependency and package imports, replacing the pre-v3 `github.com/shirou/gopsutil` path.
