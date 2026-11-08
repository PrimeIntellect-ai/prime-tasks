Add kind_sorter support for SecretList
Normally you can define multiple secrets in a single Secret manifest. However if you want a TLS secret then you can only have one TLS secret in the secret manifest.
Using a SecretList I can create a templates that would take an array of TLS secrets.
Unfortunately the SecretList is not part of the sort order and will be added after other manifest are installed that refer to my secrets in the secretlist.


Output of `helm version`:
version.BuildInfo{Version:"v3.2.0-rc.1", GitCommit:"7bffac813db894e06d17bac91d14ea819b5c2310", GitTreeState:"clean", GoVersion:"go1.13.10"}

Output of `kubectl version`:
Client Version: version.Info{Major:"1", Minor:"15", GitVersion:"v1.15.5", GitCommit:"20c265fef0741dd71a66480e35bd69f18351daea", GitTreeState:"clean", BuildDate:"2019-10-15T19:16:51Z", GoVersion:"go1.12.10", Compiler:"gc", Platform:"windows/amd64"}
Server Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.0", GitCommit:"9e991415386e4cf155a24b1da15becaa390438d8", GitTreeState:"clean", BuildDate:"2020-03-25T14:50:46Z", GoVersion:"go1.13.8", Compiler:"gc", Platform:"linux/amd64"}

Cloud Provider/Platform (AKS, GKE, Minikube etc.): Minikube

### Additional contract requirements

- For installation sorting, order `SecretList` after `Secret` and before `ConfigMap`; for uninstallation sorting, order `SecretList` after `ConfigMap` and before `Secret`.
