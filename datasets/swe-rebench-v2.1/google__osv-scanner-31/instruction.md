go.mod `replace` not being taken into account when reading
For example, Kubernetes go.mod has these lines:
```
require k8s.io/client-go v0.0.0
...
k8s.io/client-go => ./staging/src/k8s.io/client-go
```

and osv-scanner will incorrectly show all vulnerabilities for client-go that have introduced 0.

### Additional contract requirements

- A local replacement such as `golang.org/x/net v1.2.3 => ./fork/net` must be represented by a package with `Name: "./fork/net"` and `Version: ""`.
