(u|g)idMappings should not exist when joining an existing user ns
### Description

When reviewing #3985, we found an error when joining an existing user namespace.
Ref: https://github.com/opencontainers/runc/pull/3985#discussion_r1398300077

### Steps to reproduce the issue

1. start a container test with user mapping, for example:
.linux.namespaces += [{"type": "user"}]
.linux.uidMappings = [{"hostID": 100000, "containerID": 0, "size": 65536}]
.linux.gidMappings = [{"hostID": 100000, "containerID": 0, "size": 65536}]

2. get the container init process's pid
runc ps test
for example the pid is 14821

3. start an new container test1 with pid 14821's user namespace, for example:
.linux.namespaces += [{"type": "user", "path": "/proc/14821/ns/user"}]


### Describe the results you received and expected

Received:
ERRO[0000] runc run failed: User namespaces enabled, but no uid mappings found.

Expected:
The container should be started successfully.

### What version of runc are you using?

all

### Host OS information

NAME="Ubuntu"
VERSION="20.04.6 LTS (Focal Fossa)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 20.04.6 LTS"
VERSION_ID="20.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
VERSION_CODENAME=focal
UBUNTU_CODENAME=focal

### Host kernel information

Linux codespaces-21ad96 6.2.0-1016-azure #16~22.04.1-Ubuntu SMP Tue Oct 10 17:11:51 UTC 2023 x86_64 x86_64 x86_64 GNU/Linux
