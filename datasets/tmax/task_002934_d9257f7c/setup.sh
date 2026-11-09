#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest pyinstaller

    mkdir -p /app
    cd /app

    # Clone gunicorn 20.1.0
    git clone --depth 1 --branch 20.1.0 https://github.com/benoitc/gunicorn.git
    cd gunicorn
    # Apply perturbation
    sed -i 's/address\[5:\]/address[6:]/g' gunicorn/sock.py
    cd /app

    # Create oracle script
    cat << 'EOF' > oracle_gen.py
#!/usr/bin/env python3
import sys
import json

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    for item in data:
        user = item.get('user', '')
        sock = item.get('sock', '')
        quota = item.get('quota_used', 0)

        down_suffix = " down; # Quota exceeded" if quota > 1048576 else ";"
        print(f"upstream backend_{user} {{")
        print(f"    server unix:{sock}{down_suffix}")
        print("}")

if __name__ == '__main__':
    main()
EOF

    # Compile oracle script to binary
    pyinstaller --onefile oracle_gen.py
    mv dist/oracle_gen /app/oracle_gen
    chmod +x /app/oracle_gen

    # Clean up
    rm -rf build dist oracle_gen.py oracle_gen.spec

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
