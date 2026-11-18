#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential git
    pip3 install pytest setuptools setuptools_scm wheel

    mkdir -p /app
    git clone --branch 5.4.0 https://github.com/ultrajson/ultrajson.git /app/ultrajson
    # Apply perturbation
    sed -i "s/'\.\/python', '\.\/lib'//g" /app/ultrajson/setup.py

    # Create oracle
    cat << 'EOF' > /app/oracle_processor.py
import sys
import json
import ujson # Depends on agent successfully installing it, or oracle uses standard json for its own ujson emulation

def main():
    if len(sys.argv) < 2:
        return
    hex_data = sys.argv[1]
    try:
        raw_bytes = bytes.fromhex(hex_data)
        text = raw_bytes.decode('utf-8', errors='ignore')
        start = text.find('{')
        end = text.rfind('}')
        if start == -1 or end == -1 or start > end:
            print("INVALID_RECORD")
            return

        json_str = text[start:end+1]

        # Oracle simulates the ujson parsing strictness if needed, or just uses json
        parsed = json.loads(json_str)
        print(json.dumps(parsed, sort_keys=True, separators=(',', ':')))
    except Exception:
        print("INVALID_RECORD")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_processor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
