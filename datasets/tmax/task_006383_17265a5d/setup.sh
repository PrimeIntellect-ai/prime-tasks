#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/curated_repo

    touch /home/user/incoming/libA_v1.so
    touch /home/user/incoming/libB_v2.so
    touch /home/user/incoming/libC_v1.so

    cat << 'EOF' > /home/user/curator_config.ini
[DEFAULT]
LOG_FILE=/home/user/upload_log.txt
# BUG: DESTINATION=/home/user/curated_repo
MAX_RETRIES=3
EOF

    cat << 'EOF' > /home/user/upload_log.txt
START_ARTIFACT
ID=1001
STATUS=STABLE
FILE=/home/user/incoming/libA_v1.so
END_ARTIFACT
START_ARTIFACT
ID=1002
STATUS=UNSTABLE
FILE=/home/user/incoming/libB_v2.so
END_ARTIFACT
START_ARTIFACT
ID=1003
STATUS=STABLE
FILE=/home/user/incoming/libC_v1.so
END_ARTIFACT
EOF

    chmod -R 777 /home/user
