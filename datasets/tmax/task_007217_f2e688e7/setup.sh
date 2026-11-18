#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/raw_metrics.csv
timestamp,server_id,cpu_usage,mem_usage,status_code
1620000000,S1,45.5,1024,200
1620000005,S2,60.0,2048,200
1620000010,S1,-,1030,200
1620000015,S3,10.0,512,500
1620000020,S1,46.0,-,200
1620000025,S2,-,-,404
1620000030,S2,62.0,2050,999
1620000035,S1,47.0,1040,301
1620000040,S3,-,-,500
1620000045,S2,59.0,2040,200
1620000050,S1,-,1050,200
1620000055,S3,12.0,520,200
1620000060,S4,99.9,8192,503
1620000065,S1,48.0,1060,200
EOF

    chmod -R 777 /home/user
