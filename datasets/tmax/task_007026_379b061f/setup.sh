#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Commit 1: Initial Setup
    cat << 'EOF' > worker.py
import threading

class ConcurrentCache:
    def __init__(self):
        self.cache = []
        self._lock = threading.Lock()

    def add_item(self, item):
        with self._lock:
            self.cache.append(item)

    def clear(self):
        with self._lock:
            self.cache.clear()
EOF
    git add worker.py
    git commit -m "Initial commit: Add ConcurrentCache worker"

    # Commit 2: Accidental Secret Leak
    cat << 'EOF' > config.py
API_KEY = "sk-live-99a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4"
DEBUG = True
EOF
    git add config.py
    git commit -m "Add configuration file"

    # Commit 3: Remove Secret
    cat << 'EOF' > config.py
import os
API_KEY = os.environ.get("API_KEY", "")
DEBUG = True
EOF
    git add config.py
    git commit -m "Fix: Remove hardcoded API key from config"

    # Commit 4: Introduce Race Condition (Memory Leak / State Corruption)
    cat << 'EOF' > worker.py
import threading

class ConcurrentCache:
    def __init__(self):
        self.cache = []
        # Removed lock for performance

    def add_item(self, item):
        # Non-thread-safe concatenation causes missed updates and runaway duplicate references under load
        self.cache = self.cache + [item]

    def clear(self):
        self.cache = []
EOF
    git add worker.py
    git commit -m "Optimize cache updates by removing locking overhead"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
