#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest setuptools

    # Create directories
    mkdir -p /app/gq_engine-1.0.4/gq_engine
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create setup.py
    cat << 'EOF' > /app/gq_engine-1.0.4/setup.py
from setuptools import setup, find_packages
setup(
    name='gq_engine',
    version='1.0.4',
    packages=find_packages(),
)
EOF

    # Create gq_engine/__init__.py
    touch /app/gq_engine-1.0.4/gq_engine/__init__.py

    # Create gq_engine/config.py
    cat << 'EOF' > /app/gq_engine-1.0.4/gq_engine/config.py
MAX_RECURSION_DEPTH = -1
EOF

    # Create gq_engine/planner.py
    cat << 'EOF' > /app/gq_engine-1.0.4/gq_engine/planner.py
from . import config

class Plan:
    def __init__(self, max_depth, restricted_path):
        self.max_depth = max_depth
        self.restricted_path = restricted_path

    def estimate_cost(self):
        return self.max_depth * len(self.restricted_path) * 100

class QueryPlanner:
    def __init__(self, query_dict):
        self.query_dict = query_dict

    def parse(self):
        if config.MAX_RECURSION_DEPTH < 0:
            raise ValueError("Recursion depth must be >= 0")
        max_depth = self.query_dict.get('max_depth', 0)
        restricted_path = self.query_dict.get('restricted_path', [])
        return Plan(max_depth, restricted_path)
EOF

    # Create Evil Corpus
    cat << 'EOF' > /app/corpora/evil/evil_depth.json
{"max_depth": 15, "restricted_path": ["A", "B"]}
EOF

    cat << 'EOF' > /app/corpora/evil/evil_cycle.json
{"max_depth": 5, "restricted_path": ["A", "B", "A"]}
EOF

    cat << 'EOF' > /app/corpora/evil/evil_cost.json
{"max_depth": 9, "restricted_path": ["A", "B", "C", "D", "E", "F", "G"]}
EOF

    # Create Clean Corpus
    cat << 'EOF' > /app/corpora/clean/clean_1.json
{"max_depth": 5, "restricted_path": ["A", "B"]}
EOF

    cat << 'EOF' > /app/corpora/clean/clean_2.json
{"max_depth": 10, "restricted_path": ["A", "B", "C"]}
EOF

    cat << 'EOF' > /app/corpora/clean/clean_3.json
{"max_depth": 2}
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
