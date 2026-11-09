#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
192.168.1.50 GET /login?redirect=L2Rhc2hib2FyZA== 200
10.0.0.15 GET /login?redirect=aHR0cDovL2xvY2FsaG9zdC9hZG1pbg== 200
172.16.0.4 GET /login?redirect=aHR0cHM6Ly9ldmlsLmNvbS9zdGVhbA== 200
192.168.1.100 GET /login?redirect=aHR0cDovLzEwLjAuMC41L21hbHdhcmU= 200
10.0.0.22 GET /login?redirect=L2hvbWU= 200
EOF

    mkdir -p /home/user/deploy_scripts
    touch /home/user/deploy_scripts/start.sh
    touch /home/user/deploy_scripts/stop.sh
    touch /home/user/deploy_scripts/restart.sh
    touch /home/user/deploy_scripts/backup.sh

    cat << 'EOF' > /home/user/open_ports.txt
80
22
443
8080
3306
EOF

    chmod -R 777 /home/user
    chmod 755 /home/user/deploy_scripts/start.sh
    chmod 777 /home/user/deploy_scripts/stop.sh
    chmod 644 /home/user/deploy_scripts/restart.sh
    chmod 666 /home/user/deploy_scripts/backup.sh
