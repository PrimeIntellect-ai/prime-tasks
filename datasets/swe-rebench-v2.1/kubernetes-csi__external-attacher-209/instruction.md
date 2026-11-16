Incorrect repository layour for v2 Go Modules
From https://github.com/kubernetes-csi/external-snapshotter/issues/239:
```
$ go get -v github.com/kubernetes-csi/external-attacher@v2.1.0
go get github.com/kubernetes-csi/external-attacher@v2.1.0: github.com/kubernetes-csi/external-attacher@v2.1.0: invalid version: module contains a go.mod file, so major version must be compatible: should be v0 or v1, not v2
```

See https://github.com/kubernetes-csi/external-snapshotter/pull/240 for a fix.

### Additional contract requirements

- The repository must be usable as the Go module `github.com/kubernetes-csi/external-attacher/v2`, so that `go get github.com/kubernetes-csi/external-attacher@v2.1.0` resolves to it instead of being rejected as an incompatible major version.
