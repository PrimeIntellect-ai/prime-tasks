#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip bubblewrap binutils patchelf
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/auth.log
Jan 10 10:00:01 server sshd[101]: Failed password for root from 192.168.1.10 port 22 ssh2
Jan 10 10:00:05 server sshd[102]: Failed password for root from 192.168.1.10 port 22 ssh2
Jan 10 10:00:10 server sshd[103]: Failed password for root from 192.168.1.10 port 22 ssh2
Jan 10 10:00:15 server sshd[104]: Accepted password for root from 192.168.1.10 port 22 ssh2
Jan 10 10:01:00 server sshd[105]: Failed password for admin from 10.0.0.5 port 22 ssh2
Jan 10 10:01:05 server sshd[106]: Accepted password for admin from 10.0.0.5 port 22 ssh2
Jan 10 10:02:00 server sshd[107]: Failed password for user from 172.16.0.4 port 22 ssh2
Jan 10 10:02:05 server sshd[108]: Failed password for user from 172.16.0.4 port 22 ssh2
Jan 10 10:02:10 server sshd[109]: Failed password for user from 172.16.0.4 port 22 ssh2
Jan 10 10:02:15 server sshd[110]: Failed password for user from 172.16.0.4 port 22 ssh2
Jan 10 10:02:20 server sshd[111]: Accepted password for user from 172.16.0.4 port 22 ssh2
EOF

mkdir -p /home/user/binaries
cp /bin/ls /home/user/binaries/safe_ls
cp /bin/cat /home/user/binaries/suid_cat
cp /bin/echo /home/user/binaries/vuln_echo

patchelf --set-rpath /tmp /home/user/binaries/vuln_echo

chmod -R 777 /home/user
chmod 4755 /home/user/binaries/suid_cat
chmod 4755 /home/user/binaries/vuln_echo
