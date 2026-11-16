Confusing error message for invalid installFlags
Hi, I'm trying to add an `aarch64` (OrangePi 5 running https://github.com/Joshua-Riek/ubuntu-rockchip) worker node to my k0s cluster via `k0sctl` v0.15.5

`k0sctl apply --config k0s/k0sctl.yaml` fails with following in log file:

```js
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Birth: -"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `systemctl show -p FragmentPath k0sserver.service 2> /dev/null | cut -d\"=\" -f2`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `/usr/local/bin/k0s status -o json`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: (stderr) Error: status: can't do http request: /run/k0s/status.sock status"
```

It seems that it creates invalid `k0sworker.service` or `k0sserver.service` and then fails to run `k0s status -o json`.

if I ssh into the node I do have k0s binary installed, however no .service files are present nor running:

```js
$ fdfind --no-ignore k0s /
/mnt/2tb-nvme/k0s-data-dir
/usr/local/bin/k0s
/etc/k0s
/etc/k0s/k0stoken
```

And k0s status does fail:

```js
$ k0s status -o json
Error: status: can't do http request: /run/k0s/status.sock status
```

---

## Debugging info

```js
# SSH into the worker node
$ uname -a
Linux orangepi5plus1 5.10.160-rockchip #12 SMP Wed Aug 30 00:14:17 UTC 2023 aarch64 aarch64 aarch64 GNU/Linux

$ lsb_release -d
Description:	Ubuntu 22.04.3 LTS
```

k0sctl apply output:

<details>

```js
$ k0sctl apply --config k0s/k0sctl.yaml

⠀⣿⣿⡇⠀⠀⢀⣴⣾⣿⠟⠁⢸⣿⣿⣿⣿⣿⣿⣿⡿⠛⠁⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀█████████ █████████ ███
⠀⣿⣿⡇⣠⣶⣿⡿⠋⠀⠀⠀⢸⣿⡇⠀⠀⠀⣠⠀⠀⢀⣠⡆⢸⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀███          ███    ███
⠀⣿⣿⣿⣿⣟⠋⠀⠀⠀⠀⠀⢸⣿⡇⠀⢰⣾⣿⠀⠀⣿⣿⡇⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀███          ███    ███
⠀⣿⣿⡏⠻⣿⣷⣤⡀⠀⠀⠀⠸⠛⠁⠀⠸⠋⠁⠀⠀⣿⣿⡇⠈⠉⠉⠉⠉⠉⠉⠉⠉⢹⣿⣿⠀███          ███    ███
⠀⣿⣿⡇⠀⠀⠙⢿⣿⣦⣀⠀⠀⠀⣠⣶⣶⣶⣶⣶⣶⣿⣿⡇⢰⣶⣶⣶⣶⣶⣶⣶⣶⣾⣿⣿⠀█████████    ███    ██████████
k0sctl v0.15.5 Copyright 2023, k0sctl authors.
By continuing to use k0sctl you agree to these terms:
https://k0sproject.io/licenses/eula
INFO ==> Running phase: Connect to hosts
INFO [ssh] 100.64.0.1:22: connected
INFO [ssh] 100.64.0.5:22: connected
INFO ==> Running phase: Detect host operating systems
INFO [ssh] 100.64.0.1:22: is running Ubuntu 22.04.3 LTS
INFO [ssh] 100.64.0.5:22: is running Ubuntu 22.04.3 LTS
INFO ==> Running phase: Acquire exclusive host lock
INFO ==> Running phase: Prepare hosts
INFO ==> Running phase: Gather host facts
INFO [ssh] 100.64.0.1:22: using orange-pi-5-1 as hostname
INFO [ssh] 100.64.0.5:22: using orangepi5plus1 as hostname
INFO ==> Running phase: Validate hosts
INFO ==> Running phase: Gather k0s facts
INFO [ssh] 100.64.0.1:22: is running k0s controller+worker version 1.27.5+k0s.0
INFO ==> Running phase: Validate facts
INFO ==> Running phase: Configure k0s
INFO [ssh] 100.64.0.1:22: validating configuration
INFO ==> Running phase: Install workers
INFO [ssh] 100.64.0.5:22: validating api connection to https://100.64.0.1:6443
INFO [ssh] 100.64.0.1:22: generating token
INFO [ssh] 100.64.0.5:22: writing join token
INFO [ssh] 100.64.0.5:22: installing k0s worker
INFO * Running clean-up for phase: Acquire exclusive host lock
INFO * Running clean-up for phase: Install workers
ERRO apply failed - log file saved to /Users/artem_zin/Library/Caches/k0sctl/k0sctl.log
FATA failed on 1 hosts:
 - [ssh] 100.64.0.5:22: command failed: client exec: ssh session wait: Process exited with status 1
```
</details>

k0sctl.log file:

<details>

```js
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: checking if 1.27.5+k0s.0 is an upgrade from 1.27.5+k0s.0"
time="09 Sep 23 11:51 MDT" level=info msg="[ssh] 100.64.0.1:22: is running k0s controller+worker version 1.27.5+k0s.0"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `test -e /var/lib/k0s/pki/admin.conf 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `env \"KUBECONFIG=/var/lib/k0s/pki/admin.conf\" /usr/local/bin/k0s kubectl get -n kube-system namespace kube-system -o template={{.metadata.uid}}`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: dbc15819-12b3-40a2-af38-e3d902d1fc07"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `/usr/local/bin/k0s version`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: v1.27.5+k0s.0"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: has k0s binary version v1.27.5+k0s.0"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `stat /run/systemd/system`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: File: /run/systemd/system"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Size: 80        \tBlocks: 0          IO Block: 4096   directory"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Device: 19h/25d\tInode: 351         Links: 3"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: (0755/drwxr-xr-x)  Uid: (    0/    root)   Gid: (    0/    root)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: 2023-03-20 14:32:08.523333385 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Modify: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Change: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Birth: -"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `systemctl show -p FragmentPath k0scontroller.service 2> /dev/null | cut -d\"=\" -f2`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `stat /run/systemd/system`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: File: /run/systemd/system"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Size: 80        \tBlocks: 0          IO Block: 4096   directory"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Device: 19h/25d\tInode: 351         Links: 3"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: (0755/drwxr-xr-x)  Uid: (    0/    root)   Gid: (    0/    root)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: 2023-03-20 14:32:08.523333385 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Modify: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Change: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Birth: -"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `systemctl show -p FragmentPath k0sworker.service 2> /dev/null | cut -d\"=\" -f2`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `stat /run/systemd/system`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: File: /run/systemd/system"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Size: 80        \tBlocks: 0          IO Block: 4096   directory"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Device: 19h/25d\tInode: 351         Links: 3"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: (0755/drwxr-xr-x)  Uid: (    0/    root)   Gid: (    0/    root)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: 2023-03-20 14:32:08.523333385 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Modify: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Change: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Birth: -"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `systemctl show -p FragmentPath k0sserver.service 2> /dev/null | cut -d\"=\" -f2`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `/usr/local/bin/k0s status -o json`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: (stderr) Error: status: can't do http request: /run/k0s/status.sock status"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: an existing k0s instance is not running and does not seem to have been installed as a service"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Validate facts'"
time="09 Sep 23 11:51 MDT" level=info msg="\x1b[32m==> Running phase: Validate facts\x1b[0m"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Upload k0s binaries to hosts'"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Download k0s on hosts'"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: k0s version on target host is already v1.27.5+k0s.0"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: k0s version on target host is already v1.27.5+k0s.0"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Install k0s binaries on hosts'"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Run Before Apply Hooks'"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Prepare ARM nodes'"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Configure k0s'"
time="09 Sep 23 11:51 MDT" level=info msg="\x1b[32m==> Running phase: Configure k0s\x1b[0m"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `test -e /etc/k0s/k0s.yaml 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `cat -- /etc/k0s/k0s.yaml 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `grep -q \" generated-by-k0sctl\" \"/etc/k0s/k0s.yaml\"`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: writing k0s configuration"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `mktemp 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: /tmp/tmp.Xwr4r3OLJ3"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `cat > /tmp/tmp.Xwr4r3OLJ3`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: writing 380 bytes to command stdin"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `install -D -m 0600 -- /tmp/tmp.Xwr4r3OLJ3 /etc/k0s/k0s.yaml`"
time="09 Sep 23 11:51 MDT" level=info msg="[ssh] 100.64.0.1:22: validating configuration"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `/usr/local/bin/k0s config validate --help`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: Example:"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: k0s config validate --config path_to_config.yaml"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: Usage:"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: k0s config validate [flags]"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: Flags:"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: -c, --config string          config file, use '-' to read the config from stdin (default \"/etc/k0s/k0s.yaml\")"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --data-dir string        Data Directory for k0s (default: /var/lib/k0s). DO NOT CHANGE for an existing setup, things will break!"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: -d, --debug                  Debug logging (default: false)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --debugListenOn string   Http listenOn for Debug pprof handler (default \":6060\")"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: -h, --help                   help for validate"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --status-socket string   Full file path to the socket file. (default \"/run/k0s/status.sock\")"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: -v, --verbose                Verbose logging (default: false)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `/usr/local/bin/k0s config validate --config \"/etc/k0s/k0s.yaml\"`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: configuration did not change"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Restore cluster state'"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Initialize the k0s cluster'"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Install controllers'"
time="09 Sep 23 11:51 MDT" level=debug msg="Preparing phase 'Install workers'"
time="09 Sep 23 11:51 MDT" level=info msg="\x1b[32m==> Running phase: Install workers\x1b[0m"
time="09 Sep 23 11:51 MDT" level=info msg="[ssh] 100.64.0.5:22: validating api connection to https://100.64.0.1:6443"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `curl -kso /dev/null -w \"%{http_code}\" \"https://100.64.0.1:6443/healthz\"`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: 401"
time="09 Sep 23 11:51 MDT" level=info msg="[ssh] 100.64.0.1:22: generating token"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `/usr/local/bin/k0s token create --help`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: Create join token"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: Usage:"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: k0s token create [flags]"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: Examples:"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: k0s token create --role worker --expiry 100h //sets expiration time to 100 hours"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: k0s token create --role worker --expiry 10m  //sets expiration time to 10 minutes"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: Flags:"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --data-dir string        Data Directory for k0s (default: /var/lib/k0s). DO NOT CHANGE for an existing setup, things will break!"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: -d, --debug                  Debug logging (default: false)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --debugListenOn string   Http listenOn for Debug pprof handler (default \":6060\")"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --expiry string          Expiration time of the token. Format 1.5h, 2h45m or 300ms. (default \"0s\")"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: -h, --help                   help for create"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --role string            Either worker or controller (default \"worker\")"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --status-socket string   Full file path to the socket file. (default \"/run/k0s/status.sock\")"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: -v, --verbose                Verbose logging (default: false)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: --wait                   wait forever (default false)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `/usr/local/bin/k0s token create --role worker --expiry 10m0s --data-dir=/var/lib/k0s`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: join token ID: mjxvdf"
time="09 Sep 23 11:51 MDT" level=info msg="[ssh] 100.64.0.5:22: writing join token"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `mktemp 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: /tmp/tmp.CdgMMtWahD"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `cat > /tmp/tmp.CdgMMtWahD`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: writing 1752 bytes to command stdin"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `install -D -m 0640 -- /tmp/tmp.CdgMMtWahD /etc/k0s/k0stoken`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `stat /run/systemd/system`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: File: /run/systemd/system"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Size: 80        \tBlocks: 0          IO Block: 4096   directory"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Device: 19h/25d\tInode: 351         Links: 3"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: (0755/drwxr-xr-x)  Uid: (    0/    root)   Gid: (    0/    root)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: 2023-03-20 14:32:08.523333385 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Modify: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Change: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Birth: -"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `systemctl show -p FragmentPath k0sworker.service 2> /dev/null | cut -d\"=\" -f2`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: "
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `stat /run/systemd/system`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: File: /run/systemd/system"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Size: 80        \tBlocks: 0          IO Block: 4096   directory"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Device: 19h/25d\tInode: 351         Links: 3"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: (0755/drwxr-xr-x)  Uid: (    0/    root)   Gid: (    0/    root)"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Access: 2023-03-20 14:32:08.523333385 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Modify: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Change: 2023-03-20 14:32:08.336666700 +0000"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: Birth: -"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `systemctl status k0sworker 2> /dev/null | grep -q \"(running)\"`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `test -e '' 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=info msg="[ssh] 100.64.0.5:22: installing k0s worker"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `/usr/local/bin/k0s install worker --data-dir=/mnt/2tb-nvme/k0s-data-dir --token-file \"/etc/k0s/k0stoken\" --kubelet-extra-args=\"--node-ip=100.64.0.5\"`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: (stderr) zsh:1: unmatched \""
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `mktemp 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: /tmp/tmp.e3IBgGzilI"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `cat > /tmp/tmp.e3IBgGzilI`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: writing 35 bytes to command stdin: [REDACTED]"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `install -D -m 0600 -- /tmp/tmp.e3IBgGzilI /etc/k0s/k0stoken`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `/usr/local/bin/k0s token invalidate --data-dir=/var/lib/k0s mjxvdf`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: token mjxvdf deleted successfully"
time="09 Sep 23 11:51 MDT" level=info msg="\x1b[31m* Running clean-up for phase: Acquire exclusive host lock\x1b[0m"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: stopped lock cycle, removing file"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: stopped lock cycle, removing file"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.5:22: executing `rm -f -- /run/lock/k0sctl 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=debug msg="[ssh] 100.64.0.1:22: executing `rm -f -- /run/lock/k0sctl 2> /dev/null`"
time="09 Sep 23 11:51 MDT" level=info msg="\x1b[31m* Running clean-up for phase: Install workers\x1b[0m"
time="09 Sep 23 11:51 MDT" level=info msg="###### New session ######"
time="09 Sep 23 11:51 MDT" level=error msg="apply failed - log file saved to /Users/artem_zin/Library/Caches/k0sctl/k0sctl.log"
time="09 Sep 23 11:51 MDT" level=fatal msg="failed on 1 hosts:\n - [ssh] 100.64.0.5:22: command failed: client exec: ssh session wait: Process exited with status 1"
```
</details>

---

I remember having very similar issue with controller node on another OrangePi 5 and spent a week trying to get it to work but I wired it up back in March and now forgot what I did to solve it 🤦 , now I want to add a second machine to the cluster and am stuck completely. I've tried `k0s reset` on the node + reboots, nothing helps.

I guess I can create k0s `.service` files manually, but I am afraid to mess them up.

The issue seems to be similar to #2926 but in this case worker node doesn't even run `etcd` so setting `ETCD_UNSUPPORTED_ARCH` doesn't help.

### Additional contract requirements

When a host is validated, each install flag must be rejected if its single-quote or double-quote characters are unbalanced; flags with balanced quotes must be accepted. A rejection must return a non-empty diagnostic; its exact wording is not prescribed.
