#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk jq bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/inference_logs.csv
timestamp,model_version,latency_ms
1600000000,A,105
1600000001,A,110
1600000002,A,NaN
1600000003,A,108
1600000004,A,112
1600000005,A,109
1600000006,B,120
1600000007,B,122
1600000008,B,NaN
1600000009,B,121
1600000010,B,125
1600000011,B,119
EOF

    chmod -R 777 /home/user
