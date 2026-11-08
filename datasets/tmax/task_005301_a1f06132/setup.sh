#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest

    mkdir -p /app/vendored
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/eval_data

    # Download and extract jsonlines
    pip3 download --no-binary :all: --no-deps jsonlines==3.1.0 -d /tmp/
    tar -xzf /tmp/jsonlines-3.1.0.tar.gz -C /app/vendored/

    # Inject perturbation
    python3 -c "
import os
path = '/app/vendored/jsonlines-3.1.0/jsonlines/jsonlines.py'
with open(path, 'r') as f:
    content = f.read()
content = content.replace('def __init__(self, f, loads=None):', 'def __init__(self, f, loads=None):\n        if loads is None:\n            import json\n            def custom_loads(s):\n                if \"\\\\u\" in s:\n                    raise ValueError(\"Illegal unicode escape\")\n                return json.loads(s)\n            loads = custom_loads')
with open(path, 'w') as f:
    f.write(content)
"

    # Create corpora
    echo '{"config_state": {"key": "value"}}' > /app/corpora/clean/valid_configs_1.jsonl
    echo '{"config_state": {"key": "value2"}}' > /app/corpora/clean/valid_configs_2.jsonl

    echo '{"config_state": {"k": {"k": {"k": {"k": {"k": {"k": "v"}}}}}}}' > /app/corpora/evil/nested_bomb.jsonl
    echo '{"config_state": {"cmd": "echo hello; rm -rf /"}}' > /app/corpora/evil/shell_inject.jsonl
    echo '{"config_state": {"key": "value"' > /app/corpora/evil/malformed.jsonl

    # Create eval data
    echo '{"timestamp": 1, "server_id": "s1", "config_state": {"k": "v1"}, "memory_allocated": 100}
{"timestamp": 2, "server_id": "s1", "config_state": {"k": "v1"}, "memory_allocated": 150}
{"timestamp": 3, "server_id": "s1", "config_state": {"k": "v2"}, "memory_allocated": 200}' > /app/eval_data/telemetry.jsonl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
