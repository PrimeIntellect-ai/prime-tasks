#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /home/user/auth_processor
cd /home/user/auth_processor

git config --global user.email "dev@example.com"
git config --global user.name "Developer"

git init

# Commit 1: Initial implementation with hardcoded salt
cat << 'EOF' > processor.py
import base64
import os

SALT = "X9k2#mP"

def transform_token(token):
    # Appends salt, reverses the entire string, and base64 encodes
    combined = token + SALT
    reversed_str = combined[::-1]
    encoded = base64.b64encode(reversed_str.encode()).decode()
    return encoded

def process(token):
    encoded = transform_token(token)
    # Simulate a crash right after logging to memory buffer
    buffer = f"PROCESSED_DATA:{encoded}"
    raise Exception("Segmentation fault (core dumped)")
EOF

git add processor.py
git commit -m "Initial commit: Add token processor"

# Commit 2: Remove hardcoded salt
cat << 'EOF' > processor.py
import base64
import os

SALT = os.environ.get("APP_SALT", "")

def transform_token(token):
    # Appends salt, reverses the entire string, and base64 encodes
    combined = token + SALT
    reversed_str = combined[::-1]
    encoded = base64.b64encode(reversed_str.encode()).decode()
    return encoded

def process(token):
    encoded = transform_token(token)
    # Simulate a crash right after logging to memory buffer
    buffer = f"PROCESSED_DATA:{encoded}"
    raise Exception("Segmentation fault (core dumped)")
EOF

git add processor.py
git commit -m "Security fix: remove hardcoded salt"

# Create fake memory dump
cd /home/user
head -c 5000 /dev/urandom > core.dmp
echo -n "PROCESSED_DATA:UG0jMms5WE5JTURBLTkyNzQ4LVJFU1U=" >> core.dmp
head -c 5000 /dev/urandom >> core.dmp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
