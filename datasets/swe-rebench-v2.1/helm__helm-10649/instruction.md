IngressClass not created before Ingress
The InstallOrder should contain `IngressClass`, and it should happen before `Ingress`. Otherwise a `helm install` or `helm upgrade` will produce an error:

```
Error: UPGRADE FAILED: failed to create resource: admission webhook "vingress.elbv2.k8s.aws" denied the request: invalid ingress class: IngressClass.networking.k8s.io "name-of-ingressclass" not found
```
Besides that (but that might be treated as a different issue) the templates produced by `helm create` don't cater for an IngressClass resource.


Output of `helm version`:
```
version.BuildInfo{Version:"v3.8.0", GitCommit:"d14138609b01886f544b2025f5000351c9eb092e", GitTreeState:"clean", GoVersion:"go1.17.5"}
```

Output of `kubectl version`:
```Client Version: version.Info{Major:"1", Minor:"23", GitVersion:"v1.23.3", GitCommit:"816c97ab8cff8a1c72eccca1026f7820e93e0d25", GitTreeState:"clean", BuildDate:"2022-01-26T02:20:15Z", GoVersion:"go1.17.6", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"21+", GitVersion:"v1.21.5-eks-bc4871b", GitCommit:"5236faf39f1b7a7dabea8df12726f25608131aa9", GitTreeState:"clean", BuildDate:"2021-10-29T23:32:16Z", GoVersion:"go1.16.8", Compiler:"gc", Platform:"linux/amd64"}
```

Cloud Provider/Platform (AKS, GKE, Minikube etc.):
EKS

### Additional contract requirements

- `IngressClass` must appear immediately after `CronJob` and before `Ingress` in `InstallOrder`, and immediately after `Ingress` and before `Service` in `UninstallOrder`.
