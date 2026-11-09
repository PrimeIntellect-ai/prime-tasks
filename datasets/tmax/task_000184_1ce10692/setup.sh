#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn scipy

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/setup.py
import numpy as np
import os

# Set seed for reproducibility
np.random.seed(42)

n_corpus = 5000
n_queries = 100
dim = 384
latent_dim = 64

corpus_latent = np.random.randn(n_corpus, latent_dim)
query_latent = np.random.randn(n_queries, latent_dim)

projection = np.random.randn(latent_dim, dim)

corpus_embs = corpus_latent @ projection
query_embs = query_latent @ projection

corpus_embs += np.random.randn(n_corpus, dim) * 0.5
query_embs += np.random.randn(n_queries, dim) * 0.5

corpus_embs = corpus_embs / np.linalg.norm(corpus_embs, axis=1, keepdims=True)
query_embs = query_embs / np.linalg.norm(query_embs, axis=1, keepdims=True)

np.save('/home/user/data/corpus_embeddings.npy', corpus_embs)
np.save('/home/user/data/query_embeddings.npy', query_embs)
EOF

    python3 /home/user/data/setup.py
    rm /home/user/data/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
