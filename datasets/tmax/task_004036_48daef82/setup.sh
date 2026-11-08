#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import json
import random
import os

random.seed(42)

texts_A = ["The company reported strong earnings this quarter.", "Revenue grew by 20 percent year over year.", "Profits exceeded expectations.", "Sales are up in the European market.", "The quarterly dividend was increased.", "Investors responded positively to the financial report.", "Operating margins improved significantly.", "Cash flow remains very healthy.", "The balance sheet is stronger than ever.", "Earnings per share hit a record high."] * 4
texts_B = ["The new software update fixes several bugs.", "Users can now enjoy faster load times.", "The UI has been completely redesigned.", "Security patches were applied to the server.", "The database migration completed successfully.", "We added a new feature for data export.", "API response times have decreased.", "The mobile app is now available on both platforms.", "Authentication errors have been resolved.", "Cloud storage limits were increased for premium accounts."] * 4

# 80 valid records
records = []
current_id = 1
for t in texts_A:
    records.append({"id": current_id, "text": t, "label": "Finance"})
    current_id += 1
for t in texts_B:
    records.append({"id": current_id, "text": t, "label": "Technology"})
    current_id += 1

# 9 outliers (roughly 10% of 89 total)
outliers = [
    "Pineapple pizza is the best food.",
    "My cat slept for 14 hours today.",
    "Running shoes are on sale at the mall.",
    "The recipe calls for two cups of flour.",
    "I need to buy more coffee beans.",
    "Jupiter is the largest planet in the solar system.",
    "The guitar strings need to be replaced.",
    "He scored a hat-trick in the final match.",
    "A rare bird was spotted in the park."
]

for t in outliers:
    records.append({"id": current_id, "text": t, "label": "Finance" if random.random() > 0.5 else "Technology"})
    current_id += 1

random.shuffle(records)

with open('/home/user/raw_data.jsonl', 'w') as f:
    for r in records:
        f.write(json.dumps(r) + '\n')
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
