#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn flask fastapi uvicorn requests

    # Create vendored package directory
    mkdir -p /app/text-cleaner-pro/text_cleaner_pro

    # Generate setup.py
    cat << 'EOF' > /app/text-cleaner-pro/setup.py
from setuptools import setup, find_packages

setup(
    name="text-cleaner-pro",
    version="1.0.0",
    packages=find_packages(),
    install_requires=["numpy"],
)
EOF

    # Generate __init__.py
    touch /app/text-cleaner-pro/text_cleaner_pro/__init__.py

    # Generate core.py
    cat << 'EOF' > /app/text-cleaner-pro/text_cleaner_pro/core.py
from .utils import EMBEDDING_DIM
import numpy as np
import re

def clean_text(text):
    return re.sub(r'[^a-z0-9 ]', '', text.lower().strip()).strip()

def get_embedding(text):
    np.random.seed(sum(ord(c) for c in text)) # deterministic dummy embedding
    if EMBEDDING_DIM == 0:
        raise ValueError("Invalid embedding dimension")
    return np.random.randn(EMBEDDING_DIM).tolist()
EOF

    # Generate utils.py with the perturbation
    cat << 'EOF' > /app/text-cleaner-pro/text_cleaner_pro/utils.py
EMBEDDING_DIM = 0 # Agent must change this to 64
EOF

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create dataset
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/messy_data.csv
id,text,target
1,"  HELLO world!  ",2.5
2,"Data SCIENCE is fun.",3.1
3," messy text   here",1.2
EOF

    # Ensure permissions are open for the agent to modify the package and write to home
    chmod -R 777 /app
    chmod -R 777 /home/user
