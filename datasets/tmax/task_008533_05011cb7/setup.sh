#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np
import random

np.random.seed(42)
random.seed(42)

# Generate tickets
n_tickets = 500
ticket_ids = list(range(1, n_tickets + 1))

def generate_text(label):
    if label == 'bug':
        # Bugs tend to be slightly longer in this synthetic dataset
        length = int(np.random.normal(15, 4))
    else:
        # Features tend to be shorter
        length = int(np.random.normal(10, 3))

    length = max(3, length)
    return " ".join(["word"] * length)

labels_data = []
tickets_data = []

for tid in ticket_ids:
    if random.random() < 0.8: # 80% have labels
        label = random.choice(['bug', 'feature'])
        labels_data.append({'ticket_id': tid, 'label': label})
    else:
        label = 'unlabeled' # Will be missing from labels.csv

    text = generate_text(label if label != 'unlabeled' else 'bug')
    tickets_data.append({'ticket_id': tid, 'text': text})

pd.DataFrame(tickets_data).to_csv('/home/user/tickets.csv', index=False)
pd.DataFrame(labels_data).to_csv('/home/user/labels.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
