#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential binutils
    pip3 install pytest pandas pyinstaller

    cat << 'EOF' > /tmp/oracle.py
import sys
import pandas as pd
import warnings
warnings.filterwarnings("ignore")
try:
    df1 = pd.read_csv(sys.argv[1])
    df2 = pd.read_csv(sys.argv[2])
    df = pd.merge(df1, df2, on='id', how='outer')
    corr = df['value_x'].corr(df['value_y'])
    print(f"{corr:.4f}")
except Exception as e:
    print("0.0000")
EOF

    cd /tmp
    pyinstaller --onefile oracle.py
    mkdir -p /app
    cp dist/oracle /app/data_oracle
    strip /app/data_oracle
    chmod +x /app/data_oracle

    rm -rf /tmp/oracle* /tmp/build /tmp/dist

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
