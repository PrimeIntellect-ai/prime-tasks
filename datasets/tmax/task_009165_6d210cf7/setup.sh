#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
data = {
    'id': range(10),
    'label': [0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
    'text': [
        "error crash failed bad",
        "system crashed bad error",
        "failed connection error",
        "bad crash system",
        "error failed bad",
        "success working good",
        "working connection good",
        "success system good",
        "good working connection",
        "success good working"
    ]
}
pd.DataFrame(data).to_csv('/home/user/logs.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
