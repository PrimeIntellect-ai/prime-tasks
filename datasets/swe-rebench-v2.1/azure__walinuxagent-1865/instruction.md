[BUG] 'WARNING Dhcp client is not running' on Ubuntu 19.10
## Description

On Ubuntu 19.10

**WALinuxAgent** keeps reporting that the DHCP client is not running:
```
WARNING ExtHandler Dhcp client is not running.
WARNING ExtHandler Dhcp client is not running.
WARNING ExtHandler Dhcp client is not running.
```

However *systemd-networkd* is handling DHCP:

```
systemd-networkd[652]: eth0: DHCPv4 address 10.0.0.4/24 via 10.0.0.1
```

You probably need to add an exception and check for `systemd-networkd` like you did for Ubuntu 18:

https://github.com/Azure/WALinuxAgent/blob/e3ecde432c0fd6968bdb6d2774e316a61b3289d2/azurelinuxagent/common/osutil/ubuntu.py#L90-L93


## Version

```
# grep VERSION= /etc/os-release
VERSION="19.10 (Eoan Ermine)"

# waagent --version
/usr/sbin/waagent:27: DeprecationWarning: the imp module is deprecated in favour of importlib; see the module's documentation for alternative uses
  import imp
WALinuxAgent-2.2.40 running on ubuntu 19.10
Python: 3.7.5
Goal state agent: 2.2.42
```

Note that the `DeprecationWarning` seen above has already been reported (https://github.com/Azure/WALinuxAgent/issues/1473)

### Additional contract requirements

- The Ubuntu OS-util factory must select `Ubuntu18OSUtil` for Ubuntu versions
  `18.04`, `18.10`, `19.04`, `19.10`, and `20.04`. The Ubuntu codename is not
  used to make this selection and may be empty.
- The OS util selected for those versions must detect the DHCP client via
  `systemd-networkd`: when `systemd-networkd` is running, `get_dhcp_pid()`
  returns its process id, so Ubuntu 19.10 is not incorrectly reported as having
  no running DHCP client.
