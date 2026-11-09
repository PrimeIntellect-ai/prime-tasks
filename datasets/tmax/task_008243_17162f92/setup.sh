#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs/

    cat << 'EOF' > /home/user/logs/app1.log
INFO: Service started
DATA: XXXXXXXXXXYYYYYZZZZZZZZZZ
ERROR: Disk full warning
DATA: 00000000001111100000
INFO: Retrying operation
EOF

    cat << 'EOF' > /home/user/logs/app2.log
DATA: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
INFO: Done
DATA: ABC
EOF

    cat << 'EOF' > /home/user/logs/app3.log
INFO: Nothing to see here
ERROR: No data
EOF

    chmod -R 777 /home/user
