#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import os

data = {
    'id': range(1, 21),
    'text': [
        "Win a free iPhone now",
        "Hey, are we still on for lunch?",
        "URGENT: Your bank account has been compromised",
        np.nan,
        "Meeting at 10 AM tomorrow",
        "Claim your prize today!",
        "Can you send me the report?",
        "Exclusive offer just for you",
        "Don't forget to buy milk",
        "Congratulations! You won a lottery",
        "Let's go to the movies",
        "Limited time discount on our products",
        "Happy birthday!",
        "Get cheap meds online",
        "Are you coming to the party?",
        "Earn $5000 a week working from home",
        "See you soon",
        "Important update regarding your policy",
        "Call me back",
        "Free cash now"
    ],
    'label': [
        "spam", "ham", "spam", "ham", "ham", "spam", "ham", "spam",
        "ham", "spam", "ham", "spam", "ham", "spam", "ham", "spam",
        np.nan, "ham", "ham", "spam"
    ]
}

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
