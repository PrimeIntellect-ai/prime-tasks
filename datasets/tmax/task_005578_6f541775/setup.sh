#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy pyarrow fastparquet

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
n = 10000
is_premium = np.random.choice([0, 1], size=n)

# Premium users write slightly longer feedback on average
base_tokens = np.random.poisson(lam=12, size=n)
token_counts = base_tokens + (is_premium * np.random.poisson(lam=4, size=n))

# Interaction time is correlated with token count
interaction_time = token_counts * 2.3 + np.random.normal(10, 8, size=n)

words = ["excellent", "terrible", "okay", "service", "app", "crash", "fast", "slow", "love", "hate", "the", "a", "is", "it", "very", "much", "not", "too", "so", "well"]

feedback_text = []
for tc in token_counts:
    if tc == 0:
        feedback_text.append("")
        continue
    # Add random punctuation to test cleaning
    raw = " ".join(np.random.choice(words, size=tc))
    if np.random.rand() > 0.5:
        raw += "!!!"
    if np.random.rand() > 0.7:
        raw = raw.replace(" ", ", ", 1)
    feedback_text.append(raw)

df = pd.DataFrame({
    'user_id': range(n),
    'feedback_text': feedback_text,
    'interaction_time': interaction_time,
    'is_premium': is_premium
})

df.to_csv('/home/user/customer_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
