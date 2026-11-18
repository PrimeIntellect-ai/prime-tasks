#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    mkdir -p /app/pydatatransform-1.2.0/pydatatransform

    cat << 'EOF' > /app/pydatatransform-1.2.0/pydatatransform/__init__.py
from .core import apply_diff
EOF

    cat << 'EOF' > /app/pydatatransform-1.2.0/pydatatransform/core.py
import copy

_audit_history = []

def apply_diff(base_data, diff_data):
    # Intentional memory leak
    _audit_history.append(copy.deepcopy((base_data, diff_data)))

    result = copy.deepcopy(base_data)
    if not isinstance(diff_data, dict):
        return diff_data

    for k, v in diff_data.items():
        if isinstance(v, dict) and k in result and isinstance(result[k], dict):
            result[k] = apply_diff(result[k], v)
        else:
            result[k] = v
    return result
EOF

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.py
import sys
import os

sys.path.insert(0, "/app/pydatatransform-1.2.0")

from flask import Flask, request, jsonify
from pydatatransform import apply_diff

app = Flask(__name__)

@app.route('/api/v1/diff', methods=['POST'])
def diff():
    data = request.json
    base = data.get('base', {})
    diff_data = data.get('diff', {})
    result = apply_diff(base, diff_data)
    return jsonify(result)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8888)
EOF

    chown -R user:user /app/pydatatransform-1.2.0
    chmod -R 777 /home/user
