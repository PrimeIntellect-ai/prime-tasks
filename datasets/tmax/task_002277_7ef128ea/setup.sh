#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/temps.txt
160000|A|45
160002|A|55
160005|A|105
160003|A|ERR
160001|A|50
160004|A|60
EOF

    cat << 'EOF' > /home/user/loads.txt
160001|A|2.5
160002|A|3.0
160003|A|3.5
160000|A|2.0
160005|A|9.0
160004|A|3.6
EOF

    chmod -R 777 /home/user
