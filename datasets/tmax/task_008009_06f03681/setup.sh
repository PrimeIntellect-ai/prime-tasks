#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import json

embeddings = {
    "apple": [0.9, 0.1, 0.0, 0.2, 0.1],
    "banana": [0.8, 0.2, 0.0, 0.1, 0.1],
    "car": [0.1, 0.0, 0.9, 0.1, 0.2],
    "truck": [0.0, 0.1, 0.8, 0.2, 0.1],
    "drive": [0.1, 0.2, 0.7, 0.5, 0.0],
    "eat": [0.6, 0.5, 0.0, 0.1, 0.0],
    "tasty": [0.7, 0.6, 0.1, 0.0, 0.1],
    "fast": [0.2, 0.1, 0.7, 0.8, 0.1],
    "road": [0.1, 0.1, 0.8, 0.4, 0.2],
    "sweet": [0.8, 0.7, 0.0, 0.1, 0.2]
}

with open('/home/user/word_embeddings.json', 'w') as f:
    json.dump(embeddings, f)

sentences = [
    "apple banana eat tasty sweet", # Target (ID 0)
    "apple sweet tasty",            # ID 1
    "car truck drive fast road",    # ID 2
    "eat apple car",                # ID 3
    "truck drive road",             # ID 4
    "sweet banana tasty eat",       # ID 5
    "fast car drive road",          # ID 6
    "apple truck",                  # ID 7
    "banana tasty",                 # ID 8
    "eat sweet"                     # ID 9
]

with open('/home/user/sentences.txt', 'w') as f:
    for s in sentences:
        f.write(s + "\n")
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
