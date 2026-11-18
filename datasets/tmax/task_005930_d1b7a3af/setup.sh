#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libssl-dev sudo coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    mkdir -p /home/user/audit_system/logs

    # Create access.log
    cat << 'EOF' > /home/user/audit_system/logs/access.log
192.168.1.50 GET /index.html 200
192.168.1.51 POST /login 401
192.168.1.52 GET /dashboard 200
EOF

    # Create auth.log
    cat << 'EOF' > /home/user/audit_system/logs/auth.log
[INFO] FAILED LOGIN from 10.0.5.55 for user admin
[INFO] SUCCESS LOGIN from 192.168.1.20 for user guest
[INFO] FAILED LOGIN from 10.0.5.55 for user root
[INFO] FAILED LOGIN from 10.0.5.56 for user admin
[INFO] FAILED LOGIN from 10.0.5.55 for user test
[INFO] SUCCESS LOGIN from 10.0.5.56 for user admin
EOF

    # Create original system.log
    cat << 'EOF' > /home/user/audit_system/logs/system.log
[SYS] System booted successfully.
[SYS] Service sshd started.
EOF

    # Generate hashes.txt
    cd /home/user/audit_system/logs
    sha256sum access.log auth.log system.log > ../hashes.txt
    cd ../../../..

    # Tamper with system.log
    echo "[SYS] Unauthorized user added to sudoers." >> /home/user/audit_system/logs/system.log

    chown -R user:user /home/user
    chmod -R 777 /home/user

    # Mess up permissions as per task requirements
    chmod 777 /home/user/audit_system/logs
    chmod 666 /home/user/audit_system/logs/*.log
