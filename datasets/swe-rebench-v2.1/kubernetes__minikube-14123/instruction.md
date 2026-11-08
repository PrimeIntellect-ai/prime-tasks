feature: add doc URL to the addon list table
while reviwing this PR:https://github.com/kubernetes/minikube/pull/7603

since the URL will be different based on driver, it would be nice that if we have add the URL of the addon to the list, so they dont have to dig into the documentaiton and pain to find the URL for the regsiry

```
medmac@~/Desktop/md1 $ ./minikube-darwin-amd64 addons list
|-----------------------------|----------|--------------|
|         ADDON NAME          | PROFILE  |    STATUS    |
|-----------------------------|----------|--------------|
| dashboard                   | minikube | disabled     |
| default-storageclass        | minikube | enabled ✅   |
| efk                         | minikube | disabled     |
| freshpod                    | minikube | disabled     |
| gvisor                      | minikube | disabled     |
| helm-tiller                 | minikube | disabled     |
| ingress                     | minikube | disabled     |
| ingress-dns                 | minikube | disabled     |
| istio                       | minikube | disabled     |
| istio-provisioner           | minikube | disabled     |
| logviewer                   | minikube | disabled     |
| metrics-server              | minikube | disabled     |
| nvidia-driver-installer     | minikube | disabled     |
| nvidia-gpu-device-plugin    | minikube | disabled     |
| registry                    | minikube | enabled ✅   |
| registry-aliases            | minikube | disabled     |
| registry-creds              | minikube | disabled     |
| storage-provisioner         | minikube | enabled ✅   |
| storage-provisioner-gluster | minikube | disabled     |
|-----------------------------|----------|--------------|
```

### Additional contract requirements

- Add a function `printAddonsList(cc *config.ClusterConfig, printDocs bool)` in `cmd/minikube/cmd/config/addons_list.go` that writes the formatted addons table to `os.Stdout`.
- When `printDocs` is true, a `Docs` column is added to the table header and to every addon row. Each row's `Docs` cell contains that addon's documentation URL when one exists, and a placeholder value otherwise.
- When `cc` is nil the table has no `Profile` or `Status` columns; when `cc` is non-nil the table includes `Profile` and `Status` columns.
