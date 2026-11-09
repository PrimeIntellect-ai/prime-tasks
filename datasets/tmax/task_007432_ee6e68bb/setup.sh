#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/config_changes.log
[2023-10-24 10:00:00] IP=10.0.0.1 PAYLOAD={mode=prod;workers=2;}
[2023-10-24 10:01:00] IP=10.0.0.2 PAYLOAD={mode=prod;workers=2;}
[2023-10-24 10:02:00] IP=10.0.0.3 PAYLOAD={mode=dev;workers=1;}
[2023-10-24 10:03:00] IP=10.0.0.4 PAYLOAD={mode=prod;workers=2;}
[2023-10-24 10:04:00] IP=10.0.0.5 PAYLOAD={mode=test;workers=4;}
[2023-10-24 10:05:00] IP=10.0.0.6 PAYLOAD={mode=dev;workers=1;}
EOF

    chmod -R 777 /home/user
