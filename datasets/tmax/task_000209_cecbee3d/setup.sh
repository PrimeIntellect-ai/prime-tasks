#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(99)
texts = [
    "This is great", "Terrible experience", "I loved it", "Worst thing ever",
    "Absolutely fantastic", "Not good", "Okay but could be better", "I highly recommend it",
    "Do not buy this", "Amazing quality", "Waste of money", "Very satisfied",
    "It broke immediately", "Works as expected", "Poor customer service",
    "Best purchase I made", "Disappointing", "Superb", "Horrible", "Excellent"
] * 10 # 200 samples

labels = [1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1] * 10

df = pd.DataFrame({"review": texts, "sentiment": labels})
df.to_csv("/home/user/data.csv", index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
