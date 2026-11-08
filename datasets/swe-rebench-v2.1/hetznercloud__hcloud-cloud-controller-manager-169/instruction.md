server Y: no network with id X
Hi, I set up HA cluster with K3s. Everything works so far except that the cloud-controller was not able to find the network by id. This makes no sense because I already joined two control plane nodes. After restarting the cloud controller manually the error was gone. Looks like a caching issue. Even after minutes, the CCM was not able to recover. The issue isn't reproducible every time.

https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/7a1e3c76996f9f8351555a4c5d4a935318008104/hcloud/routes.go#L86

Script: https://github.com/StarpTech/k-andy

### Additional contract requirements

When route creation finds that cached server data does not include the configured network, it must refresh the server data and retry the lookup so a stale cache can recover without restarting the controller.
