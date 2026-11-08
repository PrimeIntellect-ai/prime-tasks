#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np

# Deterministic data generation
np.random.seed(42)

texts = [
    "The new UI features are fantastic and very fast.",
    "I found a bug in the settings page, it crashes.",
    "Performance is greatly improved in this release.",
    "Customer support was very rude on the phone.",
    "I have been waiting for my ticket to be answered for days.",
    "Can I get a refund for my subscription?",
    "The dashboard layout is confusing and hard to use.",
    "The representative helped me reset my password quickly.",
    "Product works well but lacks advanced export options.",
    "Billing department charged me twice this month."
] * 10

categories = [
    "Product", "Product", "Product", "Support", "Support", 
    "Support", "Product", "Support", "Product", "Support"
] * 10

df = pd.DataFrame({
    'id': [f"ID_{i:03d}" for i in range(100)],
    'category': categories,
    'text': texts
})

# Add some noise to texts to make them slightly unique
noise_words = ["apple", "banana", "orange", "grape", "melon"]
for i in range(100):
    df.loc[i, 'text'] = df.loc[i, 'text'] + " " + noise_words[i % 5]

df.to_csv('/home/user/feedback_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
