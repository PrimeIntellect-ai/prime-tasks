additionalUserData.data renders invalid cloud-config
**What happened:**
When using the additionalUserData.data in cloud-config format to pass cloud-init actions to an ubuntu server, cloud-init fails to run because  of the formatting

```
	failed to unmarshal arbitrary cloud-init data: yaml: line 2: block sequence entries are not allowed in this context, please check if you put valid yaml data:
	users: - name: ubuntu
	  ssh_authorized_keys:
	    - ssh-rsa ...
```

**What did you expect to happen:**

The output should be in the correct yaml format:
```
	users:
          - name: ubuntu
	     ssh_authorized_keys:
	     - ssh-rsa ....
```


**How to reproduce it:**

```
apiVersion: controlplane.cluster.x-k8s.io/v1alpha1
kind: RKE2ControlPlane
  metadata:
    name: management-cluster-control-plane
    namespace: default
  spec:
    agentConfig:
    format: cloud-config
    additionalUserData:
      data:
        users: |
          - name: ubuntu
            ssh_authorized_keys:
              - ssh-rsa ...
```


**Anything else you would like to add:**
[Miscellaneous information that will assist in solving the issue.]

There was a similar issue #212 but it was closed so maybe I'm just doing it incorrectly, is there a working example that you can share?

**Environment:**
K3s: v1.31.2+k3s1
clusterctl --core "cluster-api:v1.8.5" --infrastructure "metal3:v1.8.3" --bootstrap "rke2:v0.9.0" --control-plane "rke2:v0.9.0"
- rke provider version: rke2:v0.9.0
- OS (e.g. from `/etc/os-release`): Ubuntu 22.04 LTS

### Additional contract requirements

- For the input fragment `layout: False`, the rendered output must contain `layout: false`.
- Sequence-valued entries in additional user data must be rendered as valid YAML while preserving their entries.
