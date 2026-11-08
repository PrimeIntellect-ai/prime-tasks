Helm 3.4.0: Error: could not find protocol handler for
Helm 3.4.0 throws an error with local charts on `helm dep update` This does not error in v3.3.4

```
$ helm dep update
WARNING: "kubernetes-charts.storage.googleapis.com" is deprecated for "stable" and will be deleted Nov. 13, 2020.
WARNING: You should switch to "https://charts.helm.sh/stable"
Getting updates for unmanaged Helm repositories...
Error: could not find protocol handler for:
```

Chart.yaml:
```
apiVersion: v2
name: hex
version: 0.0.6
description: Hex
dependencies:
  - name: minio
    version: 3.4.20
    repository: https://charts.bitnami.com/bitnami
    condition: minio.enabled
  - name: postgresql
    alias: builtinpostgresql
    version: 9.1.1
    repository: https://charts.bitnami.com/bitnami
    condition: builtinpostgresql.enabled
  - name: builtinredis
    version: 10.7.11
    condition: builtinredis.enabled
  - name: hex-python-kernel
    version: 0.0.2
  - name: vault
    repository: https://helm.releases.hashicorp.com
    version: 0.6.0
    condition: vault.enabled
  - name: consul
    repository: https://helm.releases.hashicorp.com
    version: 0.24.1
    condition: vault.enabled
```

Chart.lock:
```
dependencies:
- name: minio
  repository: https://charts.bitnami.com/bitnami
  version: 3.4.20
- name: postgresql
  repository: https://charts.bitnami.com/bitnami
  version: 9.1.1
- name: builtinredis
  repository: ""
  version: 10.7.11
- name: hex-python-kernel
  repository: ""
  version: 0.0.2
- name: vault
  repository: https://helm.releases.hashicorp.com
  version: 0.6.0
- name: consul
  repository: https://helm.releases.hashicorp.com
  version: 0.24.1
digest: sha256:747e300b8b1ce24c76cc6c25346cd258592b93fd0b271f8002e14cb630af71f7
generated: "2020-08-13T13:46:16.6540269-04:00"
```

Output of `helm version`:
```
$ helm version
WARNING: "kubernetes-charts.storage.googleapis.com" is deprecated for "stable" and will be deleted Nov. 13, 2020.
WARNING: You should switch to "https://charts.helm.sh/stable"
version.BuildInfo{Version:"v3.4.0", GitCommit:"7090a89efc8a18f3d8178bf47d2462450349a004", GitTreeState:"clean", GoVersion:"go1.14.10"}
```

Output of `kubectl version`:
```
$ kubectl version
Client Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.8", GitCommit:"9f2892aab98fe339f3bd70e3c470144299398ace", GitTreeState:"clean", BuildDate:"2020-08-13T16:12:48Z", GoVersion:"go1.13.15", Compiler:"gc", Platform:"darwin/amd64"}
```

Cloud Provider/Platform (AKS, GKE, Minikube etc.):
N/A
