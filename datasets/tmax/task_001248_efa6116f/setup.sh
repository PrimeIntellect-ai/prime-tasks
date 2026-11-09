#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np

raw_data_path = '/home/user/raw_data.csv'

data = {
    'review_id': ['101', '102', '103.0', '104', '105.0'],
    'user_score': [5, 2, 4, 1, 3],
    'upvotes': [10.0, np.nan, 5.0, np.nan, 2.0],
    'review_text': [
        "This is a great product!",
        "Terrible. Broke in one day.",
        "Pretty good value for the money.",
        "Do not buy this...",
        "It is okay, nothing special."
    ]
}

df = pd.DataFrame(data)
df.to_csv(raw_data_path, index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
