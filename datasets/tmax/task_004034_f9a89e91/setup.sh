#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/py_custom_csv-0.1/py_custom_csv

    # Create setup.py for vendored package
    cat << 'EOF' > /app/py_custom_csv-0.1/setup.py
from setuptools import setup, find_packages

setup(
    name='py_custom_csv',
    version='0.1',
    packages=find_packages(),
)
EOF

    # Create __init__.py
    cat << 'EOF' > /app/py_custom_csv-0.1/py_custom_csv/__init__.py
from .parser import parse
EOF

    # Create buggy parser.py
    cat << 'EOF' > /app/py_custom_csv-0.1/py_custom_csv/parser.py
def parse(stream):
    """
    A buggy CSV parser that splits naively on newlines and 
    drops rows that don't have exactly 3 columns after splitting.
    """
    for line in stream:
        # Naive split, ignores quotes and embedded newlines
        parts = line.strip('\r\n').split(',')
        if len(parts) == 3:
            yield parts
EOF

    # Install the vendored package in editable mode
    pip3 install -e /app/py_custom_csv-0.1/

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/log_analyzer_oracle.py
import sys
import csv
import json
import re

def main():
    reader = csv.reader(sys.stdin)
    prev_messages = {}

    header_seen = False
    for row in reader:
        if not header_seen and row == ['timestamp', 'server_id', 'message']:
            header_seen = True
            continue

        if len(row) != 3:
            continue

        ts, srv, msg = row

        # Normalize
        msg = msg.lower()
        msg = re.sub(r'\s+', ' ', msg).strip()

        # Similarity
        sim = None
        if srv in prev_messages:
            prev_msg = prev_messages[srv]
            set1 = set(msg.split(' ')) if msg else set()
            set2 = set(prev_msg.split(' ')) if prev_msg else set()

            if not set1 and not set2:
                sim = 1.0
            else:
                intersection = len(set1.intersection(set2))
                union = len(set1.union(set2))
                sim = round(intersection / union, 4)

        prev_messages[srv] = msg

        out = {
            "timestamp": ts,
            "server_id": srv,
            "normalized_message": msg,
            "similarity": sim
        }
        print(json.dumps(out))

if __name__ == "__main__":
    main()
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
