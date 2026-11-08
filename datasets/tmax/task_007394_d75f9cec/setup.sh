#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs/raw/
    mkdir -p /home/user/reports/

    cat << 'EOF' > /home/user/configs/raw/base.ini
# Base configuration
app_port = 8080
db_host=localhost
debug=true
log_level = info
EOF

    cat << 'EOF' > /home/user/configs/raw/server1.ini
# Server 1 - slight drift
APP_PORT=8080
 DB_HOST = localhost 
debug=true
LOG_level=warning
debug=false
EOF

    cat << 'EOF' > /home/user/configs/raw/server2.ini
# Server 2 - heavy drift
app_port=9090
db_host=remote_db
debug=false
log_level=error
max_conn=100
EOF

    cat << 'EOF' > /home/user/configs/raw/server3.ini
# Server 3
app_port=8080
db_host=localhost
debug=false
log_level=info
EOF

    chown -R user:user /home/user/configs
    chown -R user:user /home/user/reports
    chmod -R 777 /home/user
