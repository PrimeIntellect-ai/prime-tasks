Cgroup paths containing ":" are not supported
Considering https://github.com/prometheus/procfs/blob/bc932d6aaa40fc66d46db859e9e03d954dc622c1/proc_cgroup.go#L52 it is clear that if the path contains additional ":" characters, the path will be truncated.

Colons may be inserted, for example when running kubernetes with containerd using a `systemd` cgroup-driver.

See:
* https://github.com/containerd/containerd/blob/c35b4cfed520bf4827737f294f9292ffa73bdf8b/pkg/cri/server/helpers_linux.go#L67

And how containerd parses the file: https://github.com/containerd/cgroups/blob/8a68de567b68b30602948417a7a8e99ccf00ee9b/utils.go#L305

[HIDDEN]

### Additional contract requirements

- When parsing a cgroup record, preserve the complete path, including any colons in it, rather than truncating the path at a colon.
