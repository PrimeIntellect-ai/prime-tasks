#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip time
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/train.csv
id,label
101,0
102,1
103,1
104,0
105,1
108,0
EOF

    cat << 'EOF' > /home/user/data/test.csv
id,label
106,0
107,1
108,0
109,1
102,1
110,0
EOF

    cat << 'EOF' > /home/user/data/source_A.csv
id,featA
101,0.5
102,0.6
103,0.7
104,0.1
105,0.2
106,0.9
107,0.8
108,0.4
109,0.3
110,0.55
EOF

    cat << 'EOF' > /home/user/data/source_B.csv
id,featB
101,50
102,60
103,70
104,10
105,20
106,90
107,80
108,40
109,30
110,55
EOF

    cat << 'EOF' > /home/user/inference_batch.py
import sys
import time

if len(sys.argv) != 2:
    print("Usage: python inference_batch.py <ids_file>")
    sys.exit(1)

with open(sys.argv[1], 'r') as f:
    ids = [line.strip() for line in f if line.strip()]

for i in ids:
    time.sleep(0.1) # Mock inference delay
    print(f"Prediction for {i}: 0.99")
EOF

    chmod +x /home/user/inference_batch.py
    chown -R user:user /home/user
    chmod -R 777 /home/user
