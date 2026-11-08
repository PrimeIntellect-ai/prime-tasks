#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_telemetry.txt
1|alpha|10
1|beta|20
1|gamma|30
2|alpha|20
2|beta|30
2|gamma|40
1|beta|20
3|alpha|30
3|beta|40
3|gamma|50
4|alpha|10
4|beta|20
4|gamma|30
3|alpha|30
5|alpha|20
5|beta|20
5|gamma|20
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
