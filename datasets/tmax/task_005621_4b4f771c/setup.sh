#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    # Generate 50 dummy log files
    cat << 'EOF' > /home/user/generate_logs.py
import random
random.seed(42)

vocab = ["convolutional", "network", "recurrent", "attention", "transformer", "dropout", 
         "batchnorm", "optimized", "robust", "scalable", "efficient", "linear", "regression", 
         "classification", "clustering", "deep", "learning", "model", "pipeline", "framework"]

for i in range(1, 51):
    with open(f"/home/user/artifacts/exp_{i}.log", "w") as f:
        f.write("Log started...\n")
        f.write(f"Epoch 1 loss: {random.random()}\n")
        desc = " ".join(random.sample(vocab, 5))
        f.write(f"Artifact-Desc: {desc}\n")
        f.write("Log finished.\n")
EOF
    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    # Create the retrieve.py script
    cat << 'EOF' > /home/user/retrieve.py
import sys
import math
from collections import Counter

def tfidf_cosine(docs, query):
    # Very basic TF (ignoring IDF for this simple mock to act as a BoW embedder)
    def vectorize(text):
        return Counter(text.lower().split())

    query_vec = vectorize(query)
    best_doc = None
    best_score = -1

    for doc in docs:
        doc_vec = vectorize(doc)
        # dot product
        score = sum(query_vec[w] * doc_vec.get(w, 0) for w in query_vec)
        # normalize
        mag_q = math.sqrt(sum(v**2 for v in query_vec.values()))
        mag_d = math.sqrt(sum(v**2 for v in doc_vec.values()))
        if mag_q > 0 and mag_d > 0:
            score = score / (mag_q * mag_d)
        else:
            score = 0

        if score > best_score:
            best_score = score
            best_doc = doc

    return best_doc

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: python3 retrieve.py <file> <query>")

    with open(sys.argv[1], 'r') as f:
        docs = [line.strip() for line in f if line.strip()]

    query = sys.argv[2]
    best = tfidf_cosine(docs, query)
    print(best)
EOF
    chmod +x /home/user/retrieve.py

    chmod -R 777 /home/user
