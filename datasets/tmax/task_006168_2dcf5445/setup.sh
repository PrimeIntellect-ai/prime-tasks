#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/config
    mkdir -p /home/user/logs/service_alpha
    mkdir -p /home/user/logs/service_beta

    # Create mock log files
    head -c 2048 </dev/urandom > /home/user/logs/service_alpha/access.log
    head -c 500 </dev/urandom > /home/user/logs/service_alpha/error.log
    head -c 4096 </dev/urandom > /home/user/logs/service_beta/worker.log

    # Create the config file with an intentional error for service_gamma
    cat << 'EOF' > /home/user/config/app_services.ini
[service_alpha]
log_dir = /home/user/logs/service_alpha
port = 9001

[service_beta]
log_dir = /home/user/logs/service_beta
port = 9002

[service_gamma]
log_dir = /home/user/logs/service_gamma_offline
port = 9003
EOF

    # Start a background process to simulate an active port (connectivity diagnostics)
    python3 -m http.server 9002 &
    echo $! > /home/user/mock_server.pid

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
