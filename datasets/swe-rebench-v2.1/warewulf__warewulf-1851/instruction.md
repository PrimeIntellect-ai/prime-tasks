wwctl node list --ipmi throws segmentation violation if ipmi data is nil
### Steps to reproduce

When attempting to output ipmi data with the --ipmi flag when some nodes do not have any ipmi data wwctl panics

```console
# wwctl node list --ipmi
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x20 pc=0xf0937b]
```

Example of working node, a login node that inherits ipmi user/pass/gateway from the profile
```console
# wwctl node list phx-login01 -a | grep -i Ipmi
phx-login01  Ipmi.UserName              phx-baseline                        secret_username
phx-login01  Ipmi.Password              phx-baseline                        secret_password
phx-login01  Ipmi.Gateway               phx-baseline                        192.168.xxx.1
phx-login01  Ipmi.Write                 phx-baseline                        true

# wwctl node list phx-login01 --ipmi
NODE         IPMI IPADDR  IPMI PORT  IPMI USERNAME  IPMI INTERFACE
----         -----------  ---------  -------------  --------------
phx-login01  <nil>        --         ADMIN          --
```

Example of a node that throws the error (since there is no ipmi data from the node or profile)
```console
# wwctl node list sol-login01 -a | grep -i Ipmi
# wwctl node list sol-login01 --ipmi
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x20 pc=0xf0937b]

goroutine 1 [running]:
github.com/warewulf/warewulf/internal/pkg/api/node.NodeList(0xc0006efb78)
        /builddir/build/BUILD/warewulf-4.6.0/internal/pkg/api/node/list.go:70 +0x143b
github.com/warewulf/warewulf/internal/app/wwctl/node/list.GetCommand.CobraRunE.func1(0xc00016b508, {0xc0004a7e00?, 0x4?, 0x128966a?})
        /builddir/build/BUILD/warewulf-4.6.0/internal/app/wwctl/node/list/main.go:33 +0xc5
github.com/spf13/cobra.(*Command).execute(0xc00016b508, {0xc0004a7de0, 0x2, 0x2})
        /builddir/build/BUILD/warewulf-4.6.0/vendor/github.com/spf13/cobra/command.go:985 +0xaca
github.com/spf13/cobra.(*Command).ExecuteC(0x1e9e4c0)
        /builddir/build/BUILD/warewulf-4.6.0/vendor/github.com/spf13/cobra/command.go:1117 +0x3ff
github.com/spf13/cobra.(*Command).Execute(0x100482520?)
        /builddir/build/BUILD/warewulf-4.6.0/vendor/github.com/spf13/cobra/command.go:1041 +0x13
main.main()
        /builddir/build/BUILD/warewulf-4.6.0/cmd/wwctl/main.go:13 +0x1e
```
Adding just any bit of ipmi data fixes this
```console
# wwctl node set sol-login01 --ipmiuser "notarealuser"
Are you sure you want to modify 1 nodes(s): y
# wwctl node list sol-login01 --ipmi
NODE         IPMI IPADDR  IPMI PORT  IPMI USERNAME  IPMI INTERFACE
----         -----------  ---------  -------------  --------------
sol-login01  <nil>        --         notarealuser   --
```

### Error message

```console
 wwctl node list --ipmi
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x20 pc=0xf0937b]

goroutine 1 [running]:
github.com/warewulf/warewulf/internal/pkg/api/node.NodeList(0xc000787b78)
        /builddir/build/BUILD/warewulf-4.6.0/internal/pkg/api/node/list.go:70 +0x143b
github.com/warewulf/warewulf/internal/app/wwctl/node/list.GetCommand.CobraRunE.func1(0xc0002f5508, {0xc000515ba0?, 0x4?, 0x128966a?})
        /builddir/build/BUILD/warewulf-4.6.0/internal/app/wwctl/node/list/main.go:33 +0xc5
github.com/spf13/cobra.(*Command).execute(0xc0002f5508, {0xc000515b80, 0x2, 0x2})
        /builddir/build/BUILD/warewulf-4.6.0/vendor/github.com/spf13/cobra/command.go:985 +0xaca
github.com/spf13/cobra.(*Command).ExecuteC(0x1e9e4c0)
        /builddir/build/BUILD/warewulf-4.6.0/vendor/github.com/spf13/cobra/command.go:1117 +0x3ff
github.com/spf13/cobra.(*Command).Execute(0x100482520?)
        /builddir/build/BUILD/warewulf-4.6.0/vendor/github.com/spf13/cobra/command.go:1041 +0x13
main.main()
        /builddir/build/BUILD/warewulf-4.6.0/cmd/wwctl/main.go:13 +0x1e
```

### Information on your system

```console
# wwctl version
wwctl version:   4.6.0-1
rpc version: apiPrefix:"rc1"  apiVersion:"1"  warewulfVersion:"4.6.0-1"

# cat /etc/os-release
NAME="Rocky Linux"
VERSION="8.10 (Green Obsidian)"
```

### General information

- [x] I have run `wwctl version` and reported the contents of `/etc/os-release`
- [x] I have searched the issues of this repo and believe this is not a duplicate
- [x] I have captured and reported relevant error messages and logs

### Additional contract requirements

- For a node with no IPMI data, `wwctl node list --ipmi` must render `--` for each of `IPMI IPADDR`, `IPMI PORT`, `IPMI USERNAME`, and `IPMI INTERFACE`.
