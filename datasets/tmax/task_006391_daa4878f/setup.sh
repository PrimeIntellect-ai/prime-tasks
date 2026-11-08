#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/metrics_analyzer

    cat << 'EOF' > /home/user/metrics_analyzer/analyzer.py
def fetch_stream(stream_id):
    # Simulates fetching data from an external DB
    raise NotImplementedError("Database connection failed")

def merge_and_diff(stream_a, stream_b):
    # TODO: Implement the matching, sorting, and diffing algorithm
    return []

def process_streams():
    a = fetch_stream("A")
    b = fetch_stream("B")
    return merge_and_diff(a, b)
EOF

    cat << 'EOF' > /home/user/metrics_analyzer/test_analyzer.py
import unittest
from unittest.mock import patch
from analyzer import process_streams

class TestAnalyzer(unittest.TestCase):
    def test_process_streams(self):
        # TODO: Setup mock fixture for fetch_stream and test process_streams
        pass
EOF

    cat << 'EOF' > /home/user/metrics_analyzer/main.py
import json
from analyzer import merge_and_diff

def main():
    stream_a = [(1, 10.0), (8, 20.0), (15, 30.0), (20, 40.0)]
    stream_b = [(3, 15.0), (7, 18.0), (16, 25.0), (24, 45.0)]

    result = merge_and_diff(stream_a, stream_b)

    with open('/home/user/final_diff.json', 'w') as f:
        json.dump(result, f)

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
