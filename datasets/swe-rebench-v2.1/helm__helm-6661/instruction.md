[HELM 3] Get Values return all default values of parent object
When we try to get values from a release deployed with one value set, we get the parent object with all this default value.

Steps to reproduce:
```
$ helm install ingress-controller -n ingress stable/nginx-ingress --set controller.replicaCount=5
```

with helm 2
```
$ helm get values
controller:
  replicaCount: 5
```
with helm 3
```
$ helm get values -n ingress ingress-controller
controller:
  addHeaders: {}
  admissionWebhooks:
    enabled: false
    failurePolicy: Fail
    patch:
      enabled: true
      image:
        pullPolicy: IfNotPresent
        repository: jettech/kube-webhook-certgen
        tag: v1.0.0
...
  replicaCount: 5
...
 ```

The issue seems to appear only when the value set has a parent object.
With this, there is no issue:
```
$ helm install ingress-controller -n ingress stable/nginx-ingress --set revisionHistoryLimit=15
```

Output of `helm version`:
```
version.BuildInfo{Version:"v3.0.0-beta.4", GitCommit:"7ffc879f137bd3a69eea53349b01f05e3d1d2385", GitTreeState:"dirty", GoVersion:"go1.13.1"}
```

Output of `kubectl version`:
```
Client Version: version.Info{Major:"1", Minor:"16", GitVersion:"v1.16.1", GitCommit:"d647ddbd755faf07169599a625faf302ffc34458", GitTreeState:"clean", BuildDate:"2019-10-02T23:49:07Z", GoVersion:"go1.12.9", Compiler:"gc", Platform:"darwin/amd64"}
Server Version: version.Info{Major:"1", Minor:"14", GitVersion:"v1.14.6", GitCommit:"96fac5cd13a5dc064f7d9f4f23030a6aeface6cc", GitTreeState:"clean", BuildDate:"2019-08-19T11:05:16Z", GoVersion:"go1.12.9", Compiler:"gc", Platform:"linux/amd64"}
```

Cloud Provider/Platform (AKS, GKE, Minikube etc.):
GKE, Docker-for-desktop

### Additional contract requirements

When retrieving a release's user-supplied values, an explicitly supplied nested value must be returned without adding chart defaults that were not supplied under the same parent object.
