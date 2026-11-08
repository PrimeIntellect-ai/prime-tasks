#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/process_config.py
import sys
import os
import ctypes

def process(input_str):
    # Check environment
    config_path = os.environ.get('CONFIG_PATH')
    if not config_path or not os.path.exists(os.path.join(config_path, 'settings.ini')):
        print("Error: CONFIG_PATH misconfigured or settings.ini missing.")
        sys.exit(1)

    # Artificial crash
    if input_str == "xzblk":
        ctypes.string_at(0) # Causes a Segmentation fault

    print(f"Processed {input_str} successfully.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 process_config.py <input>")
        sys.exit(1)
    process(sys.argv[1])
EOF

    chmod +x /home/user/process_config.py

    head -c 1M </dev/urandom > /home/user/core_dump.bin
    echo -n "AUTH_SEC_x92bF81mP_99xyz" >> /home/user/core_dump.bin
    head -c 1M </dev/urandom >> /home/user/core_dump.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
