#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

# Create dataset
np.random.seed(42)
words = ["good", "bad", "excellent", "terrible", "average", "fast", "slow", "quality", "cheap", "expensive", "awesome", "horrible"]
data = []
for i in range(100):
    text = " ".join(np.random.choice(words, size=np.random.randint(3, 8)))
    target = text.count("good")*0.5 + text.count("excellent")*1.0 + text.count("awesome")*1.2 - text.count("bad")*0.5 - text.count("terrible")*1.0 - text.count("horrible")*1.2 + np.random.normal(0, 0.2)
    data.append({"text": text, "target": target})

df = pd.DataFrame(data)
df.to_csv("/home/user/data.csv", index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
