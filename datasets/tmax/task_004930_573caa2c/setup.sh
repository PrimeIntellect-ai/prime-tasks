#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        curl \
        gnupg \
        wget

    # Install MongoDB
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org

    pip3 install pytest pandas numpy networkx scikit-learn gTTS

    mkdir -p /app
    mkdir -p /home/user/data
    useradd -m -s /bin/bash user || true

    # Generate data, ground truth, and audio
    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import networkx as nx
import json
from gtts import gTTS

# Generate CSV
np.random.seed(42)
n_rows = 5000
users = [f"U{i:03d}" for i in range(1, 101)]
tx_types = ['domestic_transfer', 'international_transfer', 'payment', 'withdrawal']

data = {
    'tx_id': [f"TX{i:05d}" for i in range(n_rows)],
    'sender_id': np.random.choice(users, n_rows),
    'receiver_id': np.random.choice(users, n_rows),
    'amount': np.random.uniform(10, 1000, n_rows),
    'timestamp': pd.date_range('2023-01-01', periods=n_rows, freq='T'),
    'tx_type': np.random.choice(tx_types, n_rows)
}
df = pd.DataFrame(data)
df = df[df['sender_id'] != df['receiver_id']]
df.to_csv('/home/user/data/transactions.csv', index=False)

# Filter and aggregate for ground truth
filtered = df[(df['tx_type'] == 'international_transfer') & (df['amount'] > 500)]
agg = filtered.groupby(['sender_id', 'receiver_id'])['amount'].sum().reset_index()

G = nx.DiGraph()
for _, row in agg.iterrows():
    G.add_edge(row['sender_id'], row['receiver_id'], weight=row['amount'])

pr = nx.pagerank(G, alpha=0.85, weight='weight')
with open('/app/ground_truth.json', 'w') as f:
    json.dump(pr, f)

# Generate Audio
text = "Hey, it's the manager. I need you to filter the transactions for the type 'international_transfer' with an amount strictly greater than five hundred. Group them up by sender and receiver to get the total weights, build the graph, and then compute the PageRank for all users using a damping factor of 0.85. Put the output in the JSON file. Thanks."
tts = gTTS(text)
tts.save('/app/voicemail.wav')
EOF

    python3 /tmp/setup_data.py

    # Create verification script
    cat << 'EOF' > /app/verify_metrics.py
import json
import sys
from sklearn.metrics import mean_squared_error

try:
    with open('/home/user/final_metrics.json', 'r') as f:
        pred = json.load(f)
    with open('/app/ground_truth.json', 'r') as f:
        truth = json.load(f)

    common_keys = set(pred.keys()).intersection(set(truth.keys()))
    if len(common_keys) < len(truth) * 0.9:
        print("Missing too many keys.")
        sys.exit(1)

    y_true = [truth[k] for k in common_keys]
    y_pred = [pred[k] for k in common_keys]

    mse = mean_squared_error(y_true, y_pred)
    print(f"MSE: {mse}")
    if mse <= 0.0001:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f"Verification failed: {e}")
    sys.exit(1)
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
