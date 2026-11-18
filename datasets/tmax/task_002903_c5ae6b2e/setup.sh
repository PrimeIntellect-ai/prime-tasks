#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron
    pip3 install pytest

    mkdir -p /home/user/incoming /home/user/outgoing

    cat << 'EOF' > /home/user/incoming/batch1.csv
kitten,sitting
flaw,lawn
intent,execution
EOF

    cat << 'EOF' > /home/user/incoming/batch2.csv
rosettacode,raisethysword
distance,difference
parallel,unparallel
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
