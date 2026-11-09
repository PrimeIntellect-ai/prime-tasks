#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > raw_data.csv
id,income,score
1,50000,80
2,,90
3,120000,
4,40000,75
5,,85
EOF

    cat << 'EOF' > feat_a.py
import sys, time, pandas as pd
time.sleep(0.5)
df = pd.read_csv(sys.argv[1])
out = pd.DataFrame({'id': df['id'], 'feat_A': df['income'] * 2})
out.to_csv('out_a.csv', index=False)
EOF

    cat << 'EOF' > feat_b.py
import sys, time, pandas as pd
time.sleep(2.5)
df = pd.read_csv(sys.argv[1])
out = pd.DataFrame({'id': df['id'], 'feat_B': df['score'] * 3})
out.to_csv('out_b.csv', index=False)
EOF

    cat << 'EOF' > feat_c.py
import sys, time, pandas as pd
time.sleep(1.0)
df = pd.read_csv(sys.argv[1])
out = pd.DataFrame({'id': df['id'], 'feat_C': df['income'] + df['score']})
out.to_csv('out_c.csv', index=False)
EOF

    chmod +x feat_a.py feat_b.py feat_c.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
