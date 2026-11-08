#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    mkdir -p /home/user/workspace/api-client
    cd /home/user/workspace/api-client

    cat << 'EOF' > pyproject.toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "api-client"
version = "0.1.0"
dependencies = [
    "requests",
]

[project.optional-dependencies]
test = [
    "pytest",
    "hypotesis", # BROKEN TYPO HERE
]
EOF

    cat << 'EOF' > client.py
def process_data(data: list) -> list:
    return sorted(list(set(data)))
EOF

    cat << 'EOF' > test_client.py
from hypothesis import given, strategies as st
from client import process_data

@given(st.lists(st.integers()))
def test_process_data_is_sorted(data):
    result = process_data(data)
    assert result == sorted(result)
    assert len(result) == len(set(data))
EOF

    cd /home/user/workspace
    cat << 'EOF' > data1.txt
apple
banana
cherry
date
elderberry
fig
EOF

    cat << 'EOF' > data2.txt
banana
cherry
dragonfruit
elderberry
guava
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
