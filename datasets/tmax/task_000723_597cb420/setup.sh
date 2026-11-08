#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /opt/verifier

    # Generate the audio file
    espeak -w /app/policy.wav "Attention storage admins. Any path escaping the base directory must be blocked. The rejection code is ERR_ZIP_SLIP_VIOLATION."

    # Create the oracle validator (optional but good for completeness based on ground truth)
    cat << 'EOF' > /opt/verifier/oracle_validator.py
import sys
import os

def check_path(base_dir, untrusted_path):
    try:
        abs_base = os.path.abspath(base_dir)
        if os.path.isabs(untrusted_path):
            untrusted_path = untrusted_path.lstrip('/')

        resolved_path = os.path.abspath(os.path.join(abs_base, untrusted_path))

        common = os.path.commonpath([abs_base, resolved_path])
        if common == abs_base and resolved_path != abs_base:
            print(resolved_path)
        else:
            print("ERR_ZIP_SLIP_VIOLATION")
    except Exception:
        print("ERR_ZIP_SLIP_VIOLATION")

if __name__ == "__main__":
    if len(sys.argv) == 3:
        check_path(sys.argv[1], sys.argv[2])
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
