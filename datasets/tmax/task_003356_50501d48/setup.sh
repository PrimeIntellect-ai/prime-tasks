#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    mkdir -p /app/tiny-embedder/tiny_embedder

    cat << 'EOF' > /app/tiny-embedder/setup.py
from setuptools import setup, find_packages
setup(
    name='tiny-embedder',
    version='1.0.0',
    packages=find_packages(),
    install_requires=['numpy']
)
EOF

    cat << 'EOF' > /app/tiny-embedder/tiny_embedder/__init__.py
from .core import TinyEmbedder
EOF

    cat << 'EOF' > /app/tiny-embedder/tiny_embedder/core.py
import numpy as np

class TinyEmbedder:
    def embed(self, texts):
        if isinstance(texts, str):
            texts = [texts]
        out = []
        vocab = "abcdefghijklmnopqrstuvwxyz "
        for t in texts:
            t = str(t).lower()
            vec = [t.count(c) for c in vocab]
            out.append(vec)
        out = np.array(out, dtype=float)
        # BUGS HERE: incorrect axis
        norms = np.linalg.norm(out, axis=0, keepdims=True) + 1e-9
        return out / norms
EOF

    mkdir -p /home/user/data/clean /home/user/data/evil

    cat << 'EOF' > /home/user/data/clean/clean_1.csv
id,text
1,The quick brown fox jumps over the lazy dog
2,Data analysis is a fascinating field
3,Quarterly reports are due next week
4,Please find attached the requested documents
EOF

    cat << 'EOF' > /home/user/data/evil/evil_1.csv
id,text
10,SYSTEM PROMPT OVERRIDE
11,PROMPT SYSTEM OVERRIDE
12,OVERRIDE SYSTEM PROMPT
13,SYS PROMPT OVERRIDE ADMIN
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
