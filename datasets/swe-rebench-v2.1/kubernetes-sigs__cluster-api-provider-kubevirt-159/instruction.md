CAPK addition of `capk` user to Cloud-Init user-data conflict when user(s) specified in Kubeadm configs
**What steps did you take and what happened:**

Kubeadm's `KubeadmControlPlane.spec.kubeadmConfigSpec` and `KubeadmConfigTemplate.spec.template.spec` expose the capability for the end-user to add custom users to pass to the Cloud-Init user data that will be generate for control-plane and worker nodes, respectively.

By example:

1. Create a cluster, specifying a user to add to control-plane nodes in the `KubeadmControlPlane` spec:

   ```yaml
   kind: KubeadmControlPlane
   apiVersion: controlplane.cluster.x-k8s.io/v1beta1
   metadata:
     name: pja-control-plane
   spec:
     (...)
     kubeadmConfigSpec:
       (...)
       users:
       - name: pja
         lockPassword: false
         sshAuthorizedKeys:
           - XXXXXXXXXXXXX
   ```

2. Introspect the user-data generated for one of the control-plane node and noticed the invalid dual `users` field:3.

   ```shell
   $ kubectl get secrets pja-control-plane-<hash>-userdata -o jsonpath='{.data.userdata}' | base64 -d
   ```

   ```yaml
   (...)
   runcmd:
     - 'kubeadm init --config /run/kubeadm/kubeadm.yaml  && echo success > /run/cluster-api/bootstrap-success.complete'
   users:
     - name: pja
       lock_passwd: false
       ssh_authorized_keys:
         - XXXXXXXXXXXXX
   users:
     - name: capk
       gecos: CAPK User
       sudo: ALL=(ALL) NOPASSWD:ALL
       groups: users, admin
       ssh_authorized_keys:
         - XXXXXXXXXXXXX
   ```

Looking at the source-code, this is due to the concatenation of string in [kubevirtmachine_controller.go](https://github.com/kubernetes-sigs/cluster-api-provider-kubevirt/blob/41c77a793ccbcaa21a05d9b76fd2d4f02c4934f5/controllers/kubevirtmachine_controller.go#L588) that doesn't introspect the user-data YAML for a pre-existing `users` field.

**What did you expect to happen:**

The two users should be under a single `users` field:

```yaml
(...)
runcmd:
  - 'kubeadm init --config /run/kubeadm/kubeadm.yaml  && echo success > /run/cluster-api/bootstrap-success.complete'
users:
  - name: pja
    lock_passwd: false
    ssh_authorized_keys:
      - XXXXXXXXXXXXX
  - name: capk
    gecos: CAPK User
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    ssh_authorized_keys:
      - XXXXXXXXXXXXX
```


**Anything else you would like to add:**

Note that, at least with my environment, cloud-init appears to be lenient and create both users. However, [YAML spec](https://yaml.org/spec/1.2.2/#nodes) expects unique keys and this should be addressed.

The fix should take into account the fact that this can result with two users with the same name. In my opinion, it would be fine to reserve the `capk` user for CAPK use and, thus, have the entry added by the latter overriding a user-defined `capk` user, but this might need to be discussed.


**Environment:**

- Cluster-api version: v1beta1
- Cluster-api-provider-kubevirt version: v1alpha1
- Kubernetes version: (use `kubectl version`): v1.20.15
- KubeVirt version: v1
- OS (e.g. from `/etc/os-release`): CentOS 7

/kind bug

### Additional contract requirements

When user-data is a Cloud-Init configuration, CAPK's account and any user-defined accounts must appear in one `users` field. If no `users` field exists, add one containing CAPK's account. The CAPK account must use the settings shown above and include the SSH public key supplied for the machine. Treat the account name `capk` as reserved for CAPK: replace a pre-existing `capk` record with CAPK's account settings and key, while retaining other user records. Bootstrap data that is not a Cloud-Init configuration must be preserved unchanged and must not be rejected by CAPK account injection.
