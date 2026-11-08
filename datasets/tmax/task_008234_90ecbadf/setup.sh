#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest setuptools

    mkdir -p /home/user/qa_env

    cat << 'EOF' > /home/user/qa_env/pyproject.toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "data-processor"
version = "0.1.0"
description = "QA Data Processor"
# Syntax error: missing closing quote, and missing Flask dependency
dependencies = [
    "requests >= 2.28.0
]
EOF

    cat << 'EOF' > /home/user/qa_env/app.py
from flask import Flask, request, jsonify
import zlib
import json

app = Flask(__name__)

@app.route('/migrate', methods=['POST'])
def migrate():
    # TODO: Implement migration from v1 to v2 schema and return checksum
    pass

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
