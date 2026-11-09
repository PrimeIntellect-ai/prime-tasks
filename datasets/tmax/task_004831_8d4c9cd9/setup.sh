#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_deps.csv
B02,B01
B03,B01
B04,B01
B05,B02
B06,B02
B07,B03
B08,B03
B10,B08
B11,B08
B12,B08
B13,B12
B14,B09
B15,B12
B16,B12
EOF

    cat << 'EOF' > /home/user/corrupted.txt
B04
B09
EOF

    chmod -R 777 /home/user
