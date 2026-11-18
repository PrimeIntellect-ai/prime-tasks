#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
data = {
    "date": ["2023-10-01", "2023-10-02", "2023-10-03", "2023-10-04", "2023-10-05"],
    "app1_workers": [4, 4, 8, 8, 12],
    "app1_threads": [16, 16, 16, 32, 32],
    "app2_workers": [2, 4, 4, 4, 4],
    "app2_threads": [8, 8, 16, 16, 32]
}
df = pd.DataFrame(data)
df.to_csv("/home/user/raw_configs.csv", index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
