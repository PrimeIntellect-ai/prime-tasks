#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/system_configs/cron.d
    mkdir -p /home/user/system_configs/sudoers.d
    mkdir -p /home/user/system_configs/systemd

    echo "user ALL=(ALL) /usr/bin/less" > /home/user/system_configs/sudoers.d/01-user
    echo "user ALL=(root) NOPASSWD: /usr/bin/tar" > /home/user/system_configs/sudoers.d/02-backup-vuln
    echo "* * * * * root /usr/local/bin/secure_backup.sh" > /home/user/system_configs/cron.d/backup

    cat << 'EOF' > /home/user/server_logs.log
2023-10-01T12:00:01 192.168.1.10 GET /login?redirect=L2Rhc2hib2FyZA%3D%3D 200 - User-Agent: Mozilla/5.0
2023-10-01T12:05:22 10.0.0.5 GET /api/data?ssn=123-45-6789 200 - User-Agent: curl/7.68.0
2023-10-01T12:10:05 172.16.0.4 GET /login?redirect=amF2YXNjcmlwdDphbGVydCgxKQ%3D%3D 200 - User-Agent: EvilCorp
2023-10-01T12:15:00 192.168.1.11 GET /profile Header: Bearer abcdef1234567890ABCD== 200
2023-10-01T12:20:10 10.10.10.10 GET /login?redirect=PHNjcmlwdD5zdGVhbCgpPC9zY3JpcHQ%2B 200 - User-Agent: HackerTracker
2023-10-01T12:25:00 192.168.1.12 GET /settings?ssn=987-65-4321 Header: Bearer XYZxyz9876543210abcd== 200
EOF

    chown -R user:user /home/user/system_configs
    chown user:user /home/user/server_logs.log

    chmod -R 777 /home/user
