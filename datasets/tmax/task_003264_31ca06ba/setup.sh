#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/create_data.py
import pandas as pd

data = [
    {"text": "The quick brown fox jumps over the lazy dog.", "label": "A"},
    {"text": "A fast brown fox leaps over a sleepy dog.", "label": "A"},
    {"text": "Machine learning is fascinating and powerful.", "label": "B"},
    {"text": "Artificial intelligence and machine learning are powerful.", "label": "B"},
    {"text": "I love eating pizza with extra cheese.", "label": "C"},
    {"text": "Pizza with cheese is my favorite food.", "label": "C"},
    {"text": "The quick brown fox jumps over the lazy dog.", "label": "A"},
    {"text": "Deep learning models require large datasets.", "label": "B"},
    {"text": "Neural networks need massive amounts of data.", "label": "B"},
    {"text": "I enjoy a good slice of pizza.", "label": "C"},
    {"text": "Foxes are wild animals.", "label": "A"},
    {"text": "To be or not to be, that is the question.", "label": "D"},
    {"text": "That is the question, to be or not to be.", "label": "D"},
    {"text": "Data science involves statistics and programming.", "label": "B"},
    {"text": "Programming and statistics are key to data science.", "label": "B"},
    {"text": "Pepperoni pizza is delicious.", "label": "C"},
    {"text": "The lazy dog slept all day.", "label": "A"},
    {"text": "Algorithms are step by step instructions.", "label": "B"},
    {"text": "An algorithm is a set of instructions.", "label": "B"},
    {"text": "I prefer pasta over pizza.", "label": "C"}
]

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_data.csv', index=False)
EOF
    python3 /home/user/create_data.py
    rm /home/user/create_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
