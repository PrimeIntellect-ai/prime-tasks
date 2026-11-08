Helm template throws stack overflow error when trying to use file checksum
<!-- If you need help or think you have found a bug, please help us with your issue by entering the following information (otherwise you can delete this text): -->

Output of `helm version`:
version.BuildInfo{Version:"v3.0.0", GitCommit:"e29ce2a54e96cd02ccfce88bee4f58bb6e2a28b6", GitTreeState:"clean", GoVersion:"go1.13.4"}

Output of `kubectl version`:
Client Version: version.Info{Major:"1", Minor:"14", GitVersion:"v1.14.1", GitCommit:"b7394102d6ef778017f2ca4046abbaa23b88c290", GitTreeState:"clean", BuildDate:"2019-04-08T17:11:31Z", GoVersion:"go1.12.1", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"16", GitVersion:"v1.16.3-k3s.2", GitCommit:"e7e6a3c4e9a7d80b87793612730d10a863a25980", GitTreeState:"clean", BuildDate:"2019-11-18T18:31:23Z", GoVersion:"go1.13.4", Compiler:"gc", Platform:"linux/amd64"}

Cloud Provider/Platform (AKS, GKE, Minikube etc.):
k3s

Helm template blows up when trying to use checksums. To reproduce it, simply create a helm chart with "helm create" then edit the deployment.yaml so the spec template contains:
...
template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/deployment.yaml") . | sha256sum }}
...

Try to generate the manifests with: "helm template --output-dir manifests". You will get something like the log attached.
This of course affects any other commands that rely on generating the manifests like "helm install".


[log.txt](https://github.com/helm/helm/files/3904819/log.txt)
