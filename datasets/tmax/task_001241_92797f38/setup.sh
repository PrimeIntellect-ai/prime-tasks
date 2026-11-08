#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nodejs ruby
pip3 install pytest

mkdir -p /home/user/test-env/python-pkg

# 1. Create the legacy Ruby script
cat << 'EOF' > /home/user/test-env/legacy_signer.rb
require 'digest'

def generate_checksum(payload)
    salt = "QA_ENV_SALT_123"
    Digest::SHA256.hexdigest(payload + salt)
end

if __FILE__ == $0
    puts generate_checksum('{"status":"ready","version":"1.0.0"}')
end
EOF

# 2. Create the broken Python package
cat << 'EOF' > /home/user/test-env/python-pkg/pyproject.toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "env-tester"
version = "0.1.0"
dependencies = [
    "requests==2.31.0",
    "urllib3==1.25.1" # Conflicting version constraint
]

[project.scripts]
env-tester = "env_tester.main:run"
EOF

mkdir -p /home/user/test-env/python-pkg/env_tester
touch /home/user/test-env/python-pkg/env_tester/__init__.py

cat << 'EOF' > /home/user/test-env/python-pkg/env_tester/main.py
import requests
import hashlib
import sys

def run():
    try:
        res = requests.get('http://localhost:8080/config', timeout=5)
        res.raise_for_status()
    except Exception as e:
        print(f"Failed to connect or HTTP error: {e}")
        sys.exit(1)

    payload = res.text
    if payload != '{"status":"ready","version":"1.0.0"}':
        print("Incorrect payload.")
        sys.exit(1)

    expected_hash = hashlib.sha256((payload + "QA_ENV_SALT_123").encode('utf-8')).hexdigest()
    actual_hash = res.headers.get('X-Checksum')

    if actual_hash == expected_hash:
        with open('/home/user/test-env/result.log', 'w') as f:
            f.write("SUCCESS\n")
        print("Test passed.")
    else:
        print(f"Checksum mismatch. Expected {expected_hash}, got {actual_hash}")
        sys.exit(1)

if __name__ == '__main__':
    run()
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/test-env
chmod -R 777 /home/user
