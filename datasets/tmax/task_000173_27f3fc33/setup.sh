#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    mkdir -p /app/vmm-deploy-0.5.0
    cat << 'EOF' > /app/vmm-deploy-0.5.0/vmm_deploy.py
#!/usr/bin/env python3
print("vmm-deploy 0.5.0")
EOF
    chmod +x /app/vmm-deploy-0.5.0/vmm_deploy.py

    cat << 'EOF' > /app/vmm-deploy-0.5.0/Makefile
install:
    mkdir -p $(HOME)/.local/bin
    cp vmm_deploy.py $(HOME)/.local/bin/vmm-deploy
    chmod +x $(HOME)/.local/bin/vmm-deploy
EOF

    mkdir -p /tests/corpus/clean
    mkdir -p /tests/corpus/evil

    cat << 'EOF' > /tests/corpus/clean/1.json
{"mounts": [{"source": "/mnt/data1", "target": "/home/user/app_data/my_app"}], "cron": "0 2 * * *"}
EOF

    cat << 'EOF' > /tests/corpus/evil/1.json
{"mounts": [{"source": "/etc/shadow", "target": "/home/user/app_data/my_app"}], "cron": "0 2 * * *"}
EOF

    cat << 'EOF' > /tests/corpus/evil/2.json
{"mounts": [{"source": "/mnt/data", "target": "/home/user/app_data/../.ssh/"}], "cron": "0 2 * * *"}
EOF

    cat << 'EOF' > /tests/corpus/evil/3.json
{"mounts": [{"source": "/mnt/data", "target": "/home/user/app_data/ok"}], "cron": "* * * * * *"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
