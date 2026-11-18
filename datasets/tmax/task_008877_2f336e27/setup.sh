#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest pandas

    mkdir -p /home/user/scripts /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/dataset1.csv
id,feature_alpha,feature_beta,feature_gamma,target
1,0.5,1.2,0.9,0
2,0.1,0.8,0.3,1
EOF

    cat << 'EOF' > /home/user/raw_data/dataset2.csv
id,feature_alpha,feature_beta,feature_gamma,target
3,0.9,1.1,0.1,1
4,0.4,0.5,0.8,0
EOF

    cat << 'EOF' > /home/user/scripts/extract.py
import os, sys
import pandas as pd

if len(sys.argv) != 3:
    print("Usage: extract.py <input.csv> <output.csv>")
    sys.exit(1)

# The intentional bug requiring an env var
if os.environ.get('PROCESSING_MODE') != 'strict':
    df = pd.DataFrame()
else:
    df = pd.read_csv(sys.argv[1])
    df['feature_alpha'] = df['feature_alpha'] * 2.0

df.to_csv(sys.argv[2], index=False)
EOF

    chmod +x /home/user/scripts/extract.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
