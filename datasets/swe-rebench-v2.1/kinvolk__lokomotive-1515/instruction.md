lokoctl's pre-update checks rolls back to older Kubernetes version unnecessarily
I installed a cluster with version `v0.6.1` and Kubernetes version being `v1.19.4`.

```console
$ helm history kubernetes -n kube-system
WARNING: Kubernetes configuration file is group-readable. This is insecure. Location: /home/hummer/.kube/config
WARNING: Kubernetes configuration file is world-readable. This is insecure. Location: /home/hummer/.kube/config
WARNING: "kubernetes-charts.storage.googleapis.com" is deprecated for "stable" and will be deleted Nov. 13, 2020.
WARNING: You should switch to "https://charts.helm.sh/stable" via:
WARNING: helm repo add "stable" "https://charts.helm.sh/stable" --force-update
REVISION        UPDATED                         STATUS          CHART                   APP VERSION     DESCRIPTION
1               Tue Mar 23 12:49:59 2021        deployed        kubernetes-0.1.2        v1.19.4         Install complete
```

```console
$ kubectl version -ojson | jq -r '.serverVersion.gitVersion'
v1.19.4
```

Then updated the cluster using new binary versioned `v0.7.0` using command `lokoctl cluster apply` and kubernetes version is now `v1.20.4`.


```console
$ helm history kubernetes -n kube-system
WARNING: Kubernetes configuration file is group-readable. This is insecure. Location: /home/hummer/.kube/config
WARNING: Kubernetes configuration file is world-readable. This is insecure. Location: /home/hummer/.kube/config
WARNING: "kubernetes-charts.storage.googleapis.com" is deprecated for "stable" and will be deleted Nov. 13, 2020.
WARNING: You should switch to "https://charts.helm.sh/stable" via:
WARNING: helm repo add "stable" "https://charts.helm.sh/stable" --force-update
REVISION        UPDATED                         STATUS          CHART                   APP VERSION     DESCRIPTION
1               Tue Mar 23 12:49:59 2021        superseded      kubernetes-0.1.2        v1.19.4         Install complete
2               Tue Mar 23 18:28:24 2021        superseded      kubernetes-0.1.2        v1.19.4         Rollback to 1
3               Tue Mar 23 18:32:23 2021        superseded      kubernetes-0.1.2        v1.19.4         Rollback to 1
4               Tue Mar 23 18:36:21 2021        deployed        kubernetes-0.1.3        v1.20.4         Upgrade complete
```

```console
$ kubectl version -ojson | jq -r '.serverVersion.gitVersion'
v1.20.4
```

Now I run the commnd `lokoctl cluster apply` again lokoctl during its pre-update check lokoctl has rolled back the cluster to `1.19.4` while I am using `v0.7.0` lokoctl binary. This is not desirable.

```console
$ helm history kubernetes -n kube-system
WARNING: Kubernetes configuration file is group-readable. This is insecure. Location: /home/hummer/.kube/config
WARNING: Kubernetes configuration file is world-readable. This is insecure. Location: /home/hummer/.kube/config
WARNING: "kubernetes-charts.storage.googleapis.com" is deprecated for "stable" and will be deleted Nov. 13, 2020.
WARNING: You should switch to "https://charts.helm.sh/stable" via:
WARNING: helm repo add "stable" "https://charts.helm.sh/stable" --force-update
REVISION        UPDATED                         STATUS                  CHART                   APP VERSION     DESCRIPTION
1               Tue Mar 23 12:49:59 2021        superseded              kubernetes-0.1.2        v1.19.4         Install complete
2               Tue Mar 23 18:28:24 2021        superseded              kubernetes-0.1.2        v1.19.4         Rollback to 1
3               Tue Mar 23 18:32:23 2021        superseded              kubernetes-0.1.2        v1.19.4         Rollback to 1
4               Tue Mar 23 18:36:21 2021        deployed                kubernetes-0.1.3        v1.20.4         Upgrade complete
5               Tue Mar 23 19:04:59 2021        pending-rollback        kubernetes-0.1.2        v1.19.4         Rollback to 1
```

```console
$ kubectl version -ojson | jq -r '.serverVersion.gitVersion'
v1.19.4
```

### Additional contract requirements

Add a public function `GetHistory(client HistoryClient, name string, max int) ([]*release.Release, error)` in package `pkg/helm` (import path `github.com/kinvolk/lokomotive/pkg/helm`), where `release.Release` is `helm.sh/helm/v3/pkg/release`.

`HistoryClient` is an interface with a single method `Run(name string) ([]*release.Release, error)`.

`GetHistory` must obtain the release history for `name` from `client` and return the revisions ordered by descending version, so that the first element is the newest revision. It must return at most `max` of the most recent revisions, and when `max` is larger than the number of available revisions it must return all of them.
