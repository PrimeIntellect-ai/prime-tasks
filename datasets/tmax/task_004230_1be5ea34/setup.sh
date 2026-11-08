#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(42)

# Generate base vocabulary
vocab = ["apple", "banana", "orange", "computer", "laptop", "mouse", "keyboard", "desk", "chair", "screen", 
         "phone", "charger", "cable", "headphones", "speaker", "bottle", "water", "coffee", "tea", "mug"]

docs = []
for i in range(1, 1001):
    # Random text of 10-20 words
    words = random.choices(vocab, k=random.randint(10, 20))
    docs.append({"doc_id": i, "text": " ".join(words)})

# Insert known near-duplicates
docs.append({"doc_id": 1001, "text": docs[10]["text"] + " " + docs[10]["text"].split()[0]})
docs.append({"doc_id": 1002, "text": docs[45]["text"]})
docs.append({"doc_id": 1003, "text": docs[200]["text"] + " apple banana"})
docs.append({"doc_id": 1004, "text": docs[500]["text"]})
docs.append({"doc_id": 1005, "text": docs[888]["text"]})

with open('/home/user/data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["doc_id", "text"])
    writer.writeheader()
    writer.writerows(docs)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
