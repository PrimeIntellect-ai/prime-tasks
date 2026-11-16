Install regression, cannot install using istioctl at all
#25384 broke this

```
$ go run ./istioctl/cmd/istioctl install -d manifests
This will install the default Istio profile into the cluster. Proceed? (y/N) y
Error: failed to apply manifests: open installPackagePath=manifests: no such file or directory
exit status 1
```

It seems the change also fundamentally drops out test coverage as this was not caught

### Additional contract requirements

When installing with `istioctl install -d <manifests-directory>`, the supplied directory must be used as the source of installation manifests and must not be treated as an input filename to open.
