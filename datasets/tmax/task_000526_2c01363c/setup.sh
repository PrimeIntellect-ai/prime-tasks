#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_task/raw_data/bin
    mkdir -p /home/user/audit_task/results

    # 1. Create system binaries (simulated)
    echo "echo 'ls'" > /home/user/audit_task/raw_data/bin/ls
    echo "echo 'cat'" > /home/user/audit_task/raw_data/bin/cat
    echo "echo 'malicious rootkit'" > /home/user/audit_task/raw_data/bin/ps
    echo "echo 'grep'" > /home/user/audit_task/raw_data/bin/grep

    # 2. Generate initial checksums (using the *original* intended content for 'ps')
    cd /home/user/audit_task/raw_data
    sha256sum bin/ls > checksums.sha256
    sha256sum bin/cat >> checksums.sha256
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  bin/ps" >> checksums.sha256 # Dummy invalid hash
    sha256sum bin/grep >> checksums.sha256

    # 3. Create SSH config
    cat << 'EOF' > /home/user/audit_task/raw_data/sshd_config.insecure
# Default sshd_config
Port 22
#PermitRootLogin yes
MaxAuthTries 6
#PasswordAuthentication yes
PubkeyAuthentication yes
EOF

    # 4. Create JSON logs
    cat << 'EOF' > /home/user/audit_task/raw_data/auth_logs.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "ip": "192.168.1.50", "event_type": "failed_login", "password": "password123"}
{"timestamp": "2023-10-01T10:01:00Z", "ip": "192.168.1.50", "event_type": "failed_login", "password": "admin"}
{"timestamp": "2023-10-01T10:02:00Z", "ip": "192.168.1.50", "event_type": "failed_login", "password": "root"}
{"timestamp": "2023-10-01T10:03:00Z", "ip": "192.168.1.50", "event_type": "failed_login", "password": "123"}
{"timestamp": "2023-10-01T10:04:00Z", "ip": "10.0.0.5", "event_type": "success", "secret_token": "abc123xyz"}
{"timestamp": "2023-10-01T10:05:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "qwerty"}
{"timestamp": "2023-10-01T10:06:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "password"}
{"timestamp": "2023-10-01T10:07:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "letmein"}
{"timestamp": "2023-10-01T10:08:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "admin"}
{"timestamp": "2023-10-01T10:09:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "root"}
{"timestamp": "2023-10-01T10:10:00Z", "ip": "10.0.0.8", "event_type": "failed_login", "password": "foo"}
EOF

    chown -R user:user /home/user/audit_task
    chmod -R 777 /home/user
