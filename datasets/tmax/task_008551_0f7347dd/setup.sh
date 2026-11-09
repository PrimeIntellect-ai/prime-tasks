#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence
    mkdir -p /home/user/fs_dump/bin

    echo "fake_binary_1" > /home/user/fs_dump/bin/backdoor
    echo "fake_binary_2" > /home/user/fs_dump/bin/legit
    echo "fake_binary_3" > /home/user/fs_dump/bin/suid_shell

    cat << 'EOF' > /home/user/evidence/environ.txt
USER=admin
PATH=/usr/bin:/bin
PASSWORD=supersecret_pwned_123!
HOME=/home/admin
EOF

    cat << 'EOF' > /home/user/evidence/syslog
Jan 10 10:00:01 host sshd[123]: Accepted password for root from 192.168.1.100 port 4444 ssh2
Jan 10 10:05:22 host unknown[999]: Connection received on backdoor port 1337 from 10.10.10.55
Jan 10 10:10:00 host cron[111]: pam_unix(cron:session): session opened for user root
EOF

    chmod -R 777 /home/user

    # Fix permissions for the SUID test after the global chmod
    chmod 4755 /home/user/fs_dump/bin/backdoor
    chmod 0755 /home/user/fs_dump/bin/legit
    chmod 4755 /home/user/fs_dump/bin/suid_shell
