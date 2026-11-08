#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_logs

    cat << 'EOF' > /home/user/config_logs/server_1.log
[2023-10-24 08:01:00] Config sync complete. current_load=10.0
[2023-10-24 08:02:00] Config sync complete. current_load=12.5
[2023-10-24 08:05:00] Config sync complete. current_load=15.0
[2023-10-24 08:06:00] Config sync complete. current_load=14.0
EOF

    cat << 'EOF' > /home/user/config_logs/server_2.log
[2023-10-24 08:10:00] Config sync complete. current_load=20.0
[2023-10-24 08:15:00] Config sync complete. current_load=70.0
[2023-10-24 08:16:00] Config sync complete. current_load=71.0
EOF

    cat << 'EOF' > /home/user/config_logs/server_3.log
[2023-10-24 08:20:00]   Config sync complete.  current_load=30.0
[2023-10-24 08:21:00] Config sync complete. current_load=76.0
[2023-10-24 08:22:00] Config sync complete. current_load=75.0
EOF

    chmod -R 777 /home/user
