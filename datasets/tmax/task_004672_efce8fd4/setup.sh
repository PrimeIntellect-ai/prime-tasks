#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/target

    cat << 'EOF' > /home/user/target/config.ini
[security]
secret_salt = 8f9a2b3c4d5e6f7a
EOF

    cat << 'EOF' > /home/user/target/waf_eval.py
import json
import sys
import hashlib
import configparser

def load_config():
    config = configparser.ConfigParser()
    config.read('/home/user/target/config.ini')
    return config['security']['secret_salt']

def process_request(filepath):
    salt = load_config()
    try:
        with open(filepath, 'r') as f:
            req = json.load(f)
    except Exception as e:
        print(f"Failed to load request: {e}")
        return

    headers = req.get('headers', {})
    cookie = headers.get('Cookie', '')
    token = headers.get('X-Bypass-Token', '')

    expected_token = hashlib.md5((cookie + salt).encode()).hexdigest()

    if token != expected_token:
        print("WAF Block: Invalid token.")
        return

    body = req.get('body', {})
    payload = body.get('payload', '')

    if not payload:
        print("No payload provided.")
        return

    print("Token valid. Executing payload in sandbox...")
    # Restricted execution environment
    safe_globals = {
        '__builtins__': None
    }

    try:
        exec(payload, safe_globals)
    except Exception as e:
        print(f"Sandbox execution error: {e}")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 waf_eval.py <request.json>")
        sys.exit(1)
    process_request(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
