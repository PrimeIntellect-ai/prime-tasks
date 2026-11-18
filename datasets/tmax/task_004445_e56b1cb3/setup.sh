#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_metrics.csv
1000,v1.0,45.5
1000,v1.0,45.5
1010,v1.0,46.0
1010,v1.1,-5.0
1010,v1.0,46.0
1030,v1.2,50.0
1040,v1.2,200.0
1040,v1.2,52.0
1070,v1.3,49.5
EOF

    chmod -R 777 /home/user
