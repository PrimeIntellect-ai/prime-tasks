Duplicate kubelet extra args produced by installFlags change detection
`k0sctl >=0.19.0` appears to duplicate generated extra kubelet arguments (specifically, `--node-ip` and `--hostname-override`) and reinstall k0s due to perceived changes in `installFlags`.

We have a cluster that has been stood up by `k0sctl 0.18.1` some time ago. Since then `k0sctl` has been updated to `0.19.0`.
Recently we've added several workers to this cluster's manifest and noticed that existing k0s controllers and workers were being reinstalled and restarted.

After some digging we've discovered that this has apparently happened due to a weird change in the `--kubelet-extra-args` flag value.

This is a `spec.hosts` entry for a controller node. It had no changes since the cluster had been created.
```
- hostname: <node hostname>
  privateAddress: <node address>
  ssh:
  # ...
  role: controller+worker
  dataDir: "/var/lib/k0s"
  installFlags:
    - --disable-components=konnectivity-server,metrics-server
    - --profile=custom
    - --kubelet-extra-args="--pod-infra-container-image=<internal registry>/pause:3.9"
    - --cri-socket=remote:/var/run/containerd/containerd.sock
    - --iptables-mode=nft
```
(just in case: we know the `--pod-infra-container-image` kubelet argument has long been deprecated, just haven't gotten around to removing it)

The `/etc/systemd/system/k0scontroller.service` file generated for this host by `k0sctl 0.18.1`:
```
[Unit]
Description=k0s - Zero Friction Kubernetes
Documentation=https://docs.k0sproject.io
ConditionFileIsExecutable=/usr/local/bin/k0s

After=network-online.target
Wants=network-online.target

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/usr/local/bin/k0s controller --config=/etc/k0s/k0s.yaml --cri-socket=remote:/var/run/containerd/containerd.sock --data-dir=/var/lib/k0s --disable-components=konnectivity-server,metrics-server --enable-worker=true --iptables-mode=nft --kubelet-extra-args=--pod-infra-container-image=<internal registry>/pause:3.9\x20--node-ip=<node address>\x20--hostname-override=<node hostname> --profile=custom --token-file=/etc/k0s/k0stoken

RestartSec=10
Delegate=yes
KillMode=process
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
LimitNOFILE=999999
Restart=always

[Install]
WantedBy=multi-user.target
```

The `/etc/systemd/system/k0scontroller.service` file generated and reinstalled for this host by `k0sctl 0.19.0`:
```
[Unit]
Description=k0s - Zero Friction Kubernetes
Documentation=https://docs.k0sproject.io
ConditionFileIsExecutable=/usr/local/bin/k0s

After=network-online.target
Wants=network-online.target

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/usr/local/bin/k0s controller --config=/etc/k0s/k0s.yaml --cri-socket=remote:/var/run/containerd/containerd.sock --data-dir=/var/lib/k0s --disable-components=konnectivity-server,metrics-server --enable-worker=true --iptables-mode=nft --kubelet-extra-args=--pod-infra-container-image=<internal registry>/pause:3.9\x20--node-ip=<node address>\x20--hostname-override=<node hostname>\x20--node-ip=<node address>\x20--hostname-override=<node hostname> --profile=custom --token-file=/etc/k0s/k0stoken

RestartSec=10
Delegate=yes
KillMode=process
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
LimitNOFILE=999999
Restart=always

[Install]
WantedBy=multi-user.target
```

Notice the duplicated `node-ip` and `hostname-override` arguments nested in the `kubelet-extra-args` flag.

We've also then done a separate `k0sctl apply` dry run with the same cluster manifest and saw that it would reinstall everything again. So it seems that there might be some issue with the `installFlags` change detection mechanism.

Aside from the argument duplication and some unexpected restarts, everything works fine. Rolling back to k0sctl 0.18.1 solves this issue for us for now.

### Additional contract requirements

- Add a public function `Unquote(input string) (string, error)` in package `github.com/k0sproject/k0sctl/internal/shell` that removes POSIX-style shell quoting and backslash escapes and returns the interpreted literal.
- Add a public method `Each(fn func(string, string))` on `Flags` in package `github.com/k0sproject/k0sctl/pkg/apis/k0sctl.k0sproject.io/v1beta1/cluster` that visits each flag in stored order, splits it into a key and a value (handling quoted values) and invokes the callback for each pair.
- Add a public method `Map() map[string]string` on `Flags` that maps each flag key to its value, using an empty string for flags without a value.
- Add a public method `Equals(other Flags) bool` on `Flags` that reports whether two flag sets contain exactly the same keys and values.
- Add a public method `K0sInstallFlags() (Flags, error)` on `Host` that assembles the complete set of flags that would be passed to `k0s install`.
- Add a public method `FlagsChanged() bool` on `Host` that reports whether the flags that would be generated now differ from the flags recorded in `Host.Metadata.K0sStatusArgs`.
- Add a public method `K0sInstallCommand() (string, error)` on `Host` that returns the full `k0s install` command.
- Generated `--node-ip` and `--hostname-override` kubelet arguments must not be duplicated when they are already present in the host's kubelet extra arguments, and a host whose configuration has not changed must not be reported as changed.
- For a `single` host with `DataDir` `/tmp/data`, install flags `--foo='bar'` and `--kubelet-extra-args="--bar=foo --foo='bar'"`, and configured token and config paths `/tmp/token` and `/tmp/foo.yaml`, `K0sInstallFlags().Join()` must be exactly `--foo=bar --kubelet-extra-args='--bar=foo --foo='"'"'bar'"'"'' --data-dir=/tmp/data --single=true --token-file=/tmp/token --config=/tmp/foo.yaml`.
- For a worker host with `DataDir` `/tmp/k0s` and token path `from-configurer`, `K0sInstallCommand()` must return exactly `k0s install worker --data-dir=/tmp/k0s --token-file=from-configurer`.
