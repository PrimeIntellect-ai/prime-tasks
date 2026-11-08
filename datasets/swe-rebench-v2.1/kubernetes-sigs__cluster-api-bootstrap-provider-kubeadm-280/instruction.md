Pre/PostKubeadmCommands are not properly escaped
/kind bug

**What steps did you take and what happened:**

I applied the following `KubeadmConfig` configuration:
```yaml
---
apiVersion: bootstrap.cluster.x-k8s.io/v1alpha2
kind: KubeadmConfig
metadata:
  name: controlplane-0
spec:
  joinConfiguration:
    controlPlane: {}
    nodeRegistration:
      name: 'test1-controlplane-0'
  postKubeadmCommands:
    - "sed 's/{{ .PodSubnet }}/192.168.0.0\\/16/' /kind/manifests/default-cni.yaml > /tmp/default-cni.yaml"
    - "kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /tmp/default-cni.yaml"
```

Which resulted in the following `runcmd` being rendered and stored in the `.Status.BootstrapData`:

```yaml
runcmd:
  - 'kubeadm join --config /tmp/kubeadm-controlplane-join-config.yaml'
  - 'sed 's/{{ .PodSubnet }}/192.168.0.0\/16/' /kind/manifests/default-cni.yaml > /tmp/default-cni.yaml'
  - 'kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /tmp/default-cni.yaml'
```

When this BootstrapData was executed by CAPD (that's the only provider I've tried with this so far), it resulted in the following error:

```
I0830 03:31:04.600521       1 machine.go:142] DockerMachine-controller "level"=0 "msg"="Running machine bootstrap scripts" "cluster"="test1" "docker-cluster"="test1" "docker-machine"={"Namespace":"test1","Name":"controlplane-0"} "machine"="controlplane-0"
E0830 03:31:04.605028       1 machine.go:145] DockerMachine-controller "msg"="" "error"="cloud-config is not valid yaml: error converting YAML to JSON: yaml: line 74: did not find expected '-' indicator" "cluster"="test1" "docker-cluster"="test1" "docker-machine"={"Namespace":"test1","Name":"controlplane-0"} "machine"="controlplane-0"
E0830 03:31:04.605541       1 controller.go:218] controller-runtime/controller "msg"="Reconciler error" "error"="failed to exec DockerMachine bootstrap: failed to join a control plane node with kubeadm: cloud-config is not valid yaml: error converting YAML to JSON: yaml: line 74: did not find expected '-' indicator"  "controller"="dockermachine" "request"={"Namespace":"test1","Name":"controlplane-0"}
```

This in turn made the CAPD unable to provision the node.

**What did you expect to happen:**

I expected the `runcmd:` section to be appropriately escaped, so that the quotes used in the `KubeadmConfig` spec didn't matter.

**Anything else you would like to add:**

Switching from:
```yaml
...
  postKubeadmCommands:
    - "sed 's/{{ .PodSubnet }}/192.168.0.0\\/16/' /kind/manifests/default-cni.yaml > /tmp/default-cni.yaml"
    - "kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /tmp/default-cni.yaml"
```
to:
```yaml
  postKubeadmCommands:
    - 'sed "s/{{ .PodSubnet }}/192.168.0.0\\/16/" /kind/manifests/default-cni.yaml > /tmp/default-cni.yaml'
    - 'kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /tmp/default-cni.yaml'
```

Worked just fine though.

**Environment:**

- Cluster API version:
```
gcr.io/k8s-staging-cluster-api/cluster-api-controller    latest    f387a1543134    6 hours ago
  42.4MB
```
- Cluster API Bootstrap Provider Kubeadm version:
```
gcr.io/k8s-staging-capi-kubeadm/cluster-api-kubeadm-controller    latest    001af5a9b57b    6 hours ago    43.3MB
```
- Cluster API Infrastructure Provider version:
```
jbergius/capd-manager    2f4a918    da5158aae882    23 hours ago    157MB
```
- Kubernetes version: (use `kubectl version`): `1.15.3`
- OS (e.g. from `/etc/os-release`): `Ubuntu 19.04`

### Additional contract requirements

- In the rendered cloud-init YAML, the command `"echo $(date) ': hello world!'"` must appear as `"\"echo $(date) ': hello world!'\""`, and the command `echo $(date) ': hello world!'` must appear as `"echo $(date) ': hello world!'"`.
