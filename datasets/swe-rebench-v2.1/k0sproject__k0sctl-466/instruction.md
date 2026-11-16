Issues with `known_hosts` and `kubectl` when using `k0sctl` to create then reset an IPv6 cluster
I have a config like this:

```yaml
apiVersion: k0sctl.k0sproject.io/v1beta1
kind: Cluster
metadata:
  name: k0s-cluster
spec:
  - ssh:
      address: 2600:1f13:2fc:8803:76b1:42d7:be29:16f8
      user: ubuntu
      port: 22
      keyPath: <redacted>
    role: controller+worker
  k0s:
    version: 1.26.1+k0s.0
    dynamicConfig: false
```

When I run `k0sctl apply --config k0sctl.yaml` and then `k0sctl reset -f --config k0sctl.yaml` I get this error during the reset:

```
k0sctl v0.15.0 Copyright 2022, k0sctl authors.
Anonymized telemetry of usage will be sent to the authors.
By continuing to use k0sctl you agree to these terms:
https://k0sproject.io/licenses/eula
INFO ==> Running phase: Connect to hosts
ERRO [SSH] 2600:1f13:2fc:8803:76b1:42d7:be29:16f8: failed to connect: not connected: client connect: can't connect: create config: can't connect: create host key validator: check hostkey: knownhosts callback: knownhosts: /home/ubuntu/.ssh/known_hosts:1: address [2600:1f13:2fc:8803:76b1:42d7:be29:16f8]: missing port in address
FATA failed on 1 hosts:
 - [ssh] [2600:1f13:2fc:8803:76b1:42d7:be29:16f8]:22: not connected: client connect: can't connect: create config: can't connect: create host key validator: check hostkey: knownhosts callback: knownhosts: /home/ubuntu/.ssh/known_hosts:1: address [2600:1f13:2fc:8803:76b1:42d7:be29:16f8]: missing port in address
```

The reset command works if I remove the corresponding line from `known_hosts`, but I have to do that before each `k0sctl` command.

Relatedly, the output of `k0sctl kubeconfig > ~/.kube/config` appears to be incompatible with `kubectl`.
Here, the server line is `server: https://2600:1f13:2fc:8803:76b1:42d7:be29:16f8:6443`.
If I run `kubectl get pods -A` I get timeout errors like:

```
E0210 18:22:57.065456   66074 memcache.go:238] couldn't get current server API group list: Get "https://2600:1f13:2fc:8803:76b1:42d7:be29:16f8:6443/api?timeout=32s": net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)
```

I believe the correct line would be `server: https://[2600:1f13:2fc:8803:76b1:42d7:be29:16f8]:6443` (note the brackets).

### Additional contract requirements

The required change is limited to the kubeconfig server address generation: when the controller address is an IPv6 address, the generated kubeconfig server URL must wrap the address in brackets before the port (for example `https://[2600:1f13:2fc:8803:76b1:42d7:be29:16f8]:6443`).
