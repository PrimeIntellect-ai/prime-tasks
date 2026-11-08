#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    mkdir -p /home/user/logs /home/user/system_state

    cat << 'EOF' > /home/user/logs/frontend.log
2023-10-25T10:00:00Z [INFO] Service initialized.
2023-10-25T10:01:05Z [ERROR] Backend unreachable, retrying...
2023-10-25T10:01:10Z [ERROR] Connection timed out.
EOF

    cat << 'EOF' > /home/user/logs/backend.log
1698228001 [INFO] Backend daemon starting.
1698228062 [FATAL] Crash detected: Dependency error.
1698228063 [INFO] Shutting down.
EOF

    cat << 'EOF' > /home/user/system_state/packages.txt
requests==2.28.1
numpy==1.24.2
urllib3==1.26.14
flask==2.2.2
EOF

    cat << 'EOF' > /home/user/system_state/app_requirements.txt
requests==2.28.1
numpy==1.23.5
flask==2.2.2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
