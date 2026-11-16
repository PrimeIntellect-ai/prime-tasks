Spegel don't start in version >=0.0.25
### Spegel version

`>=0.0.25`

### Kubernetes distribution

kubeadm

### Kubernetes version

1.30.8

### CNI

flannel

### Describe the bug

Hi, I've had Spegel running for few months without any issues on version 0.0.23. Today I decided to upgrade it, I upgraded Helm Chart to 0.0.24 and everything was fine. So then I tried update to 0.0.25 (or any hgher) and pods are crashing with very weird message I wasn't even able to find in Spegel's source code. No version since 0.0.25 works up until latest.

# Update method:

```
$ helm upgrade --create-namespace -n spegel -i --version v0.0.25 spegel oci://ghcr.io/spegel-org/helm-charts/spegel -f spegel/spegel.values.yaml
```

just in case, this is what I have in my valuess:
```yaml
resources:
  requests:
    cpu: 10m
    memory: 24Mi
  limits:
    cpu: 1
    memory: 64Mi
```

And pod logs:

```
$ k -n spegel logs -f pod/spegel-wj7d8
Defaulted container "registry" out of: registry, configuration (init)
{"time":"2025-02-07T22:32:06.08283206Z","level":"ERROR","source":{"function":"main.main","file":"/build/main.go","line":89},"msg":"run exit with error","err":"Invalid Semantic Version"}
```

My Helm version is:
```
version.BuildInfo{Version:"v3.16.4", GitCommit:"7877b45b63f95635153b29a42c0c2f4273ec45ca", GitTreeState:"dirty", GoVersion:"go1.23.4"}
```

### Additional contract requirements

- Containerd runtime versions may include distribution-specific suffixes (for example `1.6.20~ds1`) that are not SemVer compliant. Such versions must be handled without error.
- Containerd configuration verification is performed for runtime versions below 2.0.0 and skipped for runtime versions at or above 2.0.0.
