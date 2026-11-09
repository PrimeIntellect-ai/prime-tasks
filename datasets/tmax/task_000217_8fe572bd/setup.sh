#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/srv1_run1.conf
server_port=8080
max_connections=100
db_host=localhost
timestamp=1698400000
EOF

    cat << 'EOF' > /home/user/configs/srv1_run2.conf
server_port=8080
max_connections=100
db_host=localhost
timestamp=1698400005
EOF

    cat << 'EOF' > /home/user/configs/srv2_run1.conf
server_port=9090
max_connections=500
db_host=remote-db
timestamp=1698400000
EOF

    cat << 'EOF' > /home/user/configs/srv1_run3.conf
server_port=8080
max_connections=100
db_host=localhost
timestamp=1698400010
EOF

    cat << 'EOF' > /home/user/configs/srv3_run1.conf
server_port=7070
max_connections=50
db_host=127.0.0.1
timestamp=1698400000
EOF

    cat << 'EOF' > /home/user/deploy.log
[2023-10-27 10:00:00] [INFO] Starting deployment pipeline
[2023-10-27 10:00:01] [DEBUG] Fetching variables
[2023-10-27 10:00:02] [INFO] Deployed config to /home/user/configs/srv1_run1.conf
[2023-10-27 10:00:03] [ERROR] Connection lost, retrying srv1...
[2023-10-27 10:00:05] [INFO] Deployed config to /home/user/configs/srv1_run2.conf
[2023-10-27 10:00:06] [INFO] Deployed config to /home/user/configs/srv2_run1.conf
[2023-10-27 10:00:07] [WARNING] Timeout on srv1 verification, retrying...
[2023-10-27 10:00:10] [INFO] Deployed config to /home/user/configs/srv1_run3.conf
[2023-10-27 10:00:11] [INFO] Deployed config to /home/user/configs/srv3_run1.conf
[2023-10-27 10:00:12] [INFO] Deployment pipeline finished
EOF

    chown -R user:user /home/user/configs /home/user/deploy.log
    chmod -R 777 /home/user
