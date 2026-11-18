#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk
    pip3 install pytest

    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/experiments/run_1.csv
epoch,loss,accuracy,latency_ms
1,0.9,0.50,120
2,0.6,0.70,121
3,0.3,0.85,120
EOF

    cat << 'EOF' > /home/user/experiments/run_2.csv
epoch,loss,accuracy,latency_ms
1,0.8,0.60,150
2,0.4,0.88,149
3,0.2,0.92,150
EOF

    cat << 'EOF' > /home/user/experiments/run_3.csv
epoch,loss,accuracy,latency_ms
1,0.95,0.55,110
2,0.55,0.75,112
3,0.25,0.88,110
EOF

    cat << 'EOF' > /home/user/experiments/run_4.csv
epoch,loss,accuracy,latency_ms
1,0.7,0.65,200
2,0.3,0.90,198
3,0.1,0.95,200
EOF

    cat << 'EOF' > /home/user/experiments/run_5.csv
epoch,loss,accuracy,latency_ms
1,1.0,0.40,90
2,0.8,0.60,95
3,0.5,0.79,90
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
