panic caused by nil point
### How to use it?

- [X] kwok
- [ ] kwokctl --runtime=docker (default runtime)
- [ ] kwokctl --runtime=binary
- [ ] kwokctl --runtime=nerdctl
- [ ] kwokctl --runtime=kind

### What happened?

There is a panic when I execute kwok with `--manage-nodes-with-label-selector=node-role.kubernetes.io/worker`:


```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x1595ba6]

goroutine 82 [running]:
sigs.k8s.io/kwok/pkg/kwok/controllers.(*NodeController).needLockNode(0xc000514600, 0xc0002cc000)
	/opt/tiger/compile_path/src/code.byted.org/godel/kwok/pkg/kwok/controllers/node_controller.go:164 +0x26
sigs.k8s.io/kwok/pkg/kwok/controllers.(*NodeController).WatchNodes.func1()
	/opt/tiger/compile_path/src/code.byted.org/godel/kwok/pkg/kwok/controllers/node_controller.go:215 +0x1a6
created by sigs.k8s.io/kwok/pkg/kwok/controllers.(*NodeController).WatchNodes
	/opt/tiger/compile_path/src/code.byted.org/godel/kwok/pkg/kwok/controllers/node_controller.go:190 +0x2ec
```

### What did you expect to happen?

Expect to execute kwok with `--manage-nodes-with-label-selector=node-role.kubernetes.io/worker` successfully.

### How can we reproduce it (as minimally and precisely as possible)?

Execute kwok wtih `--manage-nodes-with-label-selector=node-role.kubernetes.io/worker`:

### Anything else we need to know?

_No response_

### Kwok version

<details>

```console
$ kwok --version
kwok version ad2f53b

```
</details>


### OS version

<details>

```console
$ cat /etc/os-release
  PRETTY_NAME="Debian GNU/Linux 9 (stretch)"
  NAME="Debian GNU/Linux"
  VERSION_ID="9"
  VERSION="9 (stretch)"
  VERSION_CODENAME=stretch
  ID=debian
  HOME_URL="https://www.debian.org/"
  SUPPORT_URL="https://www.debian.org/support"
  BUG_REPORT_URL="https://bugs.debian.org/

$ uname -a
  Linux kind-simulator-control-plane 5.4.143.bsk.8-amd64 #5.4.143.bsk.8 SMP Debian 5.4.143.bsk.8 Wed Jul 20 08:43:36 UTC  x86_64 GNU/Linux

```
</details>
