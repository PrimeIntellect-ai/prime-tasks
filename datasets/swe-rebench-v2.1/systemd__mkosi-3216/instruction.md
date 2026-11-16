Unable to reset list variables to empty list from CLI
### mkosi commit the issue has been seen with

main

### Used host distribution

Fedora 40

### Used target distribution

Fedora 40

### Linux kernel version used

6.11.6-200.fc40.x86_64

### CPU architectures issue was seen on

x86_64

### Unexpected behaviour you saw

Invoking mkosi with `mkosi --build-source= --build-source=foobar` does not result in `foobar` being the only build script. Instead, the clearing is ignored and `foobar` is simply appended to the list of build scripts. Only passing `--build-source=`, however, does work to clear the list.

### Used mkosi config

```ini
This repo
```


### mkosi output

```sh
septatrix@Framework-13-AMD ~/D/p/mkosi (main)> bin/mkosi --json summary | jq .Images[-1].PrepareScripts
[
  "/home/septatrix/Documents/programming/mkosi/mkosi.prepare",
  "/home/septatrix/Documents/programming/mkosi/mkosi.prepare.chroot"
]
septatrix@Framework-13-AMD ~/D/p/mkosi (main)> bin/mkosi --json --prepare-script= summary | jq .Images[-1].PrepareScripts
[]
septatrix@Framework-13-AMD ~/D/p/mkosi (main)> bin/mkosi --json --prepare-script= --prepare-script=mkosi.prepare summary | jq .Images[-1].PrepareScripts
[
  "/home/septatrix/Documents/programming/mkosi/mkosi.prepare",
  "/home/septatrix/Documents/programming/mkosi/mkosi.prepare.chroot",
  "/home/septatrix/Documents/programming/mkosi/mkosi.prepare"
]
septatrix@Framework-13-AMD ~/D/p/mkosi (main)> bin/mkosi --debug --prepare-script= --prepare-script=mkosi.prepare summary > /dev/null
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.local.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf
‣ Loading configuration file /tmp/tmpnmbs4fsq/resources/mkosi-vm/mkosi.conf
‣ Loading configuration file /tmp/tmpnmbs4fsq/resources/mkosi-vm/mkosi.conf.d/azure-centos-fedora/mkosi.conf
‣ Loading configuration file /tmp/tmpnmbs4fsq/resources/mkosi-vm/mkosi.conf.d/azure-centos-fedora/mkosi.conf.d/networkd.conf
‣ Loading configuration file /tmp/tmpnmbs4fsq/resources/mkosi-vm/mkosi.conf.d/azure-centos-fedora/mkosi.conf.d/uefi.conf
‣ Loading configuration file /tmp/tmpnmbs4fsq/resources/mkosi-vm/mkosi.conf
‣ Loading configuration file /tmp/tmpnmbs4fsq/resources/mkosi-vm/mkosi.conf.d/azure-centos-fedora/mkosi.conf
‣ Loading configuration file /tmp/tmpnmbs4fsq/resources/mkosi-vm/mkosi.conf.d/azure-centos-fedora/mkosi.conf.d/networkd.conf
‣ Loading configuration file /tmp/tmpnmbs4fsq/resources/mkosi-vm/mkosi.conf.d/azure-centos-fedora/mkosi.conf.d/uefi.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/15-bootable.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/15-x86-64.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/20-fedora/mkosi.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/20-fedora/mkosi.conf.d/20-x86_64.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/30-azure-centos-fedora/mkosi.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/30-azure-centos-fedora/mkosi.conf.d/20-uefi.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/30-azure-centos-fedora/mkosi.conf.d/20-x86-64.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/40-tools/mkosi.conf
‣ Loading configuration file /home/septatrix/Documents/programming/mkosi/mkosi.conf.d/40-tools/mkosi.conf.d/other.conf
‣ + tput cnorm
‣ + tput smam
```
