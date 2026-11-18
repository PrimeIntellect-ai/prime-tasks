#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create vendor package with perturbation
    mkdir -p /app/vendor/filelock-3.12.2/src/filelock
    touch /app/vendor/filelock-3.12.2/pyproject.toml

    cat << 'EOF' > /app/vendor/filelock-3.12.2/pyproject.toml
[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"
[project]
name = "filelock"
version = "3.12.2"
dependencies = []
EOF

    cat << 'EOF' > /app/vendor/filelock-3.12.2/src/filelock/__init__.py
from ._unix import FileLock
EOF

    cat << 'EOF' > /app/vendor/filelock-3.12.2/src/filelock/_unix.py
import os
class FileLock:
    def __init__(self, path):
        self.path = path
    def acquire(self):
        # PERTURBATION: O_EXCLL instead of O_EXCL
        fd = os.open(self.path, os.O_CREAT | os.O_WRONLY | os.O_EXCLL)
        os.close(fd)
    def __enter__(self):
        self.acquire()
        return self
    def __exit__(self, exc_type, exc_val, exc_tb):
        pass
EOF

    # Create corpus directories
    mkdir -p /app/corpus/clean/bundle1/nested
    echo '{"UUID": "1111", "version": "1.0"}' > /app/corpus/clean/bundle1/nested/meta.json
    mkdir -p /app/corpus/evil/bundle1
    echo '{"UUID": "2222", "version": "1.0"' > /app/corpus/evil/bundle1/meta.json # invalid json
    mkdir -p /app/corpus/evil/bundle2
    ln -s . /app/corpus/evil/bundle2/loop # symlink loop
    echo '{"UUID": "3333", "version": "1.0"}' > /app/corpus/evil/bundle2/meta.json

    # Verifier secret corpora
    mkdir -p /app/verifier_corpus/clean/b1/dir
    echo '{"UUID": "abc", "version": "9"}' > /app/verifier_corpus/clean/b1/dir/meta.json
    mkdir -p /app/verifier_corpus/evil/b1
    echo 'bad json' > /app/verifier_corpus/evil/b1/meta.json
    mkdir -p /app/verifier_corpus/evil/b2/dir
    ln -s ../dir /app/verifier_corpus/evil/b2/dir/loop
    echo '{"UUID": "xyz", "version": "1"}' > /app/verifier_corpus/evil/b2/dir/meta.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
