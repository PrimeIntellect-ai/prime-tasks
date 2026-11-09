#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git python3-setuptools
    pip3 install pytest

    mkdir -p /home/user/legacy_pipeline/legacy_pipeline
    cd /home/user/legacy_pipeline

    # Initialize git
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Create initial files
    cat << 'EOF' > legacy_pipeline/constants.py
API_KEY = "sk-live-7x89asdf897asdf897897"
VERSION = "1.0.0"
EOF

    cat << 'EOF' > legacy_pipeline/__init__.py
# init
EOF

    cat << 'EOF' > legacy_pipeline/cli.py
import json
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: process_data <json_string>")
        sys.exit(1)

    data_str = sys.argv[1]
    try:
        data = json.loads(data_str)
    except:
        sys.exit(0) # Ignore malformed for this test

    # Artificial crash condition
    if data.get("status") == "active" and data.get("priority") == -1 and "test_flag" in data:
        # Cause a crash
        x = 1 / 0

    print("Processed successfully")
    sys.exit(0)
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, find_packages

setup(
    name="legacy_pipeline",
    version="1.0.0",
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "process_data=legacy_pipeline.cli:main",
        ],
    },
)
EOF

    git add .
    git commit -m "Initial commit with working code and secrets"

    # Break the setup.py and remove secret
    cat << 'EOF' > setup.py
from setuptools import setup, find_package # INTENTIONAL TYPO: find_package instead of find_packages

setup(
    name="legacy_pipeline",
    version="1.0.0",
    packages=find_package(),
    entry_points={
        "console_scripts": [
            "process_data=legacy_pipeline.cli:main",
        ],
    },
)
EOF

    cat << 'EOF' > legacy_pipeline/constants.py
API_KEY = "" # Removed for security
VERSION = "1.0.0"
EOF

    git add .
    git commit -m "Remove secret and update setup"

    # Create sample data
    cd /home/user
    python3 -c '
import json
import random

with open("sample_data.jsonl", "w") as f:
    for i in range(1000):
        if i == 742:
            # The crashing payload
            record = {"id": i, "status": "active", "priority": -1, "test_flag": True, "value": "crash_me"}
        else:
            record = {"id": i, "status": random.choice(["active", "inactive"]), "priority": random.randint(1, 10), "value": "data"}
        f.write(json.dumps(record) + "\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
