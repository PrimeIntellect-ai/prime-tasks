#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/proc_dumps
mkdir -p /home/user/.ssh

# Create dummy proc dumps
# PID 101
printf "bash\0-c\0echo hello\0" > /home/user/proc_dumps/101_cmdline
echo -e "Name:\tbash\nState:\tS (sleeping)\nUid:\t1000\t1000\t1000\t1000\nGid:\t1000\t1000\t1000\t1000" > /home/user/proc_dumps/101_status

# PID 202
B64_KEY="LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYmFiYWJvb2V5MTIzNDUKLS0tLS1FTkQgT1BFTlNTSCBQUklWQVRFIEtFWS0tLS0t"
printf "/usr/bin/python3\0/opt/admin_daemon.py\0--auth-token\0${B64_KEY}\0--verbose\0" > /home/user/proc_dumps/202_cmdline
echo -e "Name:\tpython3\nState:\tS (sleeping)\nUid:\t0\t0\t0\t0\nGid:\t0\t0\t0\t0" > /home/user/proc_dumps/202_status

# PID 303
B64_KEY2="ZmFrZV9rZXk="
printf "/usr/bin/python3\0/opt/user_daemon.py\0--auth-token\0${B64_KEY2}\0" > /home/user/proc_dumps/303_cmdline
echo -e "Name:\tpython3\nState:\tS (sleeping)\nUid:\t1000\t1000\t1000\t1000\nGid:\t1000\t1000\t1000\t1000" > /home/user/proc_dumps/303_status

chmod -R 777 /home/user
chmod 700 /home/user/.ssh
