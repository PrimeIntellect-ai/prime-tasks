#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/alert.wav "System alert. Error code E seven two. Server node omega nine."

    mkdir -p /home/user
    cat << 'EOF' > /home/user/nodes.csv
node_name,ip_address,owner
alpha 1,10.0.0.10,Backend-Team
omega 9,10.0.0.42,SRE-Team
zeta 3,10.0.0.55,DBA-Team
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
