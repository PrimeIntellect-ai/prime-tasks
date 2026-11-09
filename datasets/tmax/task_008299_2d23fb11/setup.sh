#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    mkdir -p /home/user/logs
    mkdir -p /home/user/www

    echo "OK" > /home/user/www/index.html

    cat << 'EOF' > /home/user/bin/get_disk_usage
#!/bin/bash
echo -n "42"
EOF
    chmod +x /home/user/bin/get_disk_usage

    cat << 'EOF' > /home/user/run_monitor.sh
#!/bin/bash
# TODO: Fix environment variables here
python3 /home/user/monitor_uptime.py
EOF
    chmod +x /home/user/run_monitor.sh

    cat << 'EOF' > /home/user/monitor_uptime.py
import os
import urllib.request
import subprocess

# TODO: Implement monitoring and logging logic
EOF

    chmod -R 777 /home/user
