#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/audit_env/logs
    mkdir -p /home/user/audit_env/config
    mkdir -p /home/user/audit_env/network

    # 1. auth.log
    cat << 'EOF' > /home/user/audit_env/logs/auth.log
Oct 10 10:00:01 server sshd[123]: Failed password for admin from 192.168.1.50 port 50123 ssh2
Oct 10 10:02:01 server sshd[123]: Failed password for admin from 192.168.1.50 port 50124 ssh2
Oct 10 10:04:01 server sshd[123]: Failed password for admin from 192.168.1.50 port 50125 ssh2
Oct 10 10:06:01 server sshd[123]: Failed password for admin from 192.168.1.50 port 50126 ssh2
Oct 10 10:08:01 server sshd[123]: Failed password for root from 192.168.1.50 port 50127 ssh2
Oct 10 10:10:01 server sshd[124]: Failed password for admin from 10.0.0.5 port 44444 ssh2
Oct 10 10:12:01 server sshd[124]: Failed password for admin from 10.0.0.5 port 44445 ssh2
Oct 10 10:15:01 server sshd[125]: Accepted password for admin from 192.168.1.100 port 50124 ssh2
Oct 10 10:16:01 server sshd[126]: Failed password for admin from 172.16.0.10 port 33333 ssh2
Oct 10 10:17:01 server sshd[126]: Failed password for admin from 172.16.0.10 port 33334 ssh2
Oct 10 10:18:01 server sshd[126]: Failed password for admin from 172.16.0.10 port 33335 ssh2
Oct 10 10:19:01 server sshd[126]: Failed password for admin from 172.16.0.10 port 33336 ssh2
Oct 10 10:20:01 server sshd[126]: Failed password for admin from 172.16.0.10 port 33337 ssh2
EOF

    # 2. sudoers (using echo to avoid Apptainer parsing %admin as a section)
    echo "root ALL=(ALL:ALL) ALL" > /home/user/audit_env/config/sudoers
    echo "%admin ALL=(ALL) ALL" >> /home/user/audit_env/config/sudoers
    echo "dev_user ALL=(ALL) NOPASSWD: ALL" >> /home/user/audit_env/config/sudoers
    echo "qa_user ALL=(ALL) NOPASSWD: /bin/systemctl" >> /home/user/audit_env/config/sudoers
    echo "backup_svc ALL=(ALL) NOPASSWD:ALL" >> /home/user/audit_env/config/sudoers
    echo "app_runner ALL=(ALL:ALL) NOPASSWD: ALL" >> /home/user/audit_env/config/sudoers

    # 3. ports.json
    cat << 'EOF' > /home/user/audit_env/network/ports.json
[
  {"port": 22, "state": "open", "service": "ssh"},
  {"port": 80, "state": "closed", "service": "http"},
  {"port": 443, "state": "open", "service": "https"},
  {"port": 3306, "state": "open", "service": "mysql"},
  {"port": 8080, "state": "open", "service": "http-proxy"},
  {"port": 9000, "state": "closed", "service": "cslistener"}
]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/audit_env
    chmod -R 777 /home/user
