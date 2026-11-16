Helm v3 Error when parsing the URL for helm chart save
### Situation

I've downloaded a chart and attempted to upload the chart to registry.
My registry is Harbor, installed in the Kubernetes cluster.
I've logged in the registry successfully with command `helm registry login -u admin --insecure 10.20.131.50:30003`
But when I tried to issue "helm chart save", it shows that the URL is incorrect
```
$ helm chart save harbor-helm/ 10.20.131.50:30003/library/harbor
Error: parse 10.20.131.50:30003/library/harbor: first path segment in URL cannot contain colon
```

while removing the port number and the colon will work

```
$ helm chart save harbor-helm/ 10.20.131.50/library/harbor:latest
ref:     10.20.131.50/library/harbor:latest
digest:  df10ae52f374f547d0f21951f72788acbdb3ae2d21c26c5e4cdb6327a7e40c48
size:    31.0 KiB
name:    harbor
version: 1.2.0-dev
latest: saved
```

but apparently that is not the correct registry endpoint, and that won't work while pushing charts to the registry.

In the [registries documentation](https://v3.helm.sh/docs/topics/registries/#the-chart-subcommand), it works perfectly with port number specified.

```
$ helm chart save mychart/ localhost:5000/myrepo/mychart:2.7.0
ref:     localhost:5000/myrepo/mychart:2.7.0
digest:  1b251d38cfe948dfc0a5745b7af5ca574ecb61e52aed10b19039db39af6e1617
size:    2.4 KiB
name:    mychart
version: 0.1.0
2.7.0: saved
```

### Version info

Output of `helm version`:
```
version.BuildInfo{Version:"v3.0.0", GitCommit:"e29ce2a54e96cd02ccfce88bee4f58bb6e2a28b6", GitTreeState:"clean", GoVersion:"go1.13.4"}
```

Output of `kubectl version`:
```
Client Version: version.Info{Major:"1", Minor:"16", GitVersion:"v1.16.2", GitCommit:"c97fe5036ef3df2967d086711e6c0c405941e14b", GitTreeState:"clean", BuildDate:"2019-10-15T19:18:23Z", GoVersion:"go1.12.10", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"16", GitVersion:"v1.16.3", GitCommit:"b3cbbae08ec52a7fc73d334838e18d17e8512749", GitTreeState:"clean", BuildDate:"2019-11-13T11:13:49Z", GoVersion:"go1.12.12", Compiler:"gc", Platform:"linux/amd64"}
```

Cloud Provider/Platform (AKS, GKE, Minikube etc.):
```
Ubuntu 18.04.3 LTS (Bionic Beaver)
kubeadm provisioned cluster on bare metal
```
