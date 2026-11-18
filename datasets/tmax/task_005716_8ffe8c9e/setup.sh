#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/train_data.json
[
  "fresh organic red apple",
  "yellow ripe banana sweet",
  "green spinach leaves fresh",
  "wild blue berry fresh"
]
EOF

    cat << 'EOF' > /home/user/query_data.json
[
  "apple computer pro",
  "blueberry muffin sweet",
  "green apple fresh"
]
EOF

    cat << 'EOF' > /home/user/etl_pipeline.py
import json
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

def load_data():
    with open('/home/user/train_data.json', 'r') as f:
        train = json.load(f)
    with open('/home/user/query_data.json', 'r') as f:
        queries = json.load(f)
    return train, queries

def run_pipeline(output_log):
    train, queries = load_data()
    vectorizer = TfidfVectorizer()

    # BUG: Data leakage! Fitting on both train and queries
    all_data = train + queries
    vectorizer.fit(all_data)

    train_vecs = vectorizer.transform(train)
    query_vecs = vectorizer.transform(queries)

    sim_matrix = cosine_similarity(query_vecs, train_vecs)
    top_1_sims = np.max(sim_matrix, axis=1)
    avg_sim = float(np.mean(top_1_sims))

    with open(output_log, 'w') as f:
        json.dump({"avg_top1_similarity": avg_sim}, f)

if __name__ == "__main__":
    run_pipeline('/home/user/experiment_v1.json')
EOF

    chmod -R 777 /home/user
