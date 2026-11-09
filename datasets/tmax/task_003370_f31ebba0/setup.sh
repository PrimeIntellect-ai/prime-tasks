#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo build-essential
    pip3 install pytest

    mkdir -p /home/user/app

    python3 -c '
plaintext = b"Secret Rust FFI Migration Payload 2024!"
encoded = bytes([b ^ 0xAA for b in plaintext])
with open("/home/user/app/encoded.dat", "wb") as f:
    f.write(encoded)
'

    cat << 'EOF' > /home/user/app/legacy_process.py
import sys
import legacy_c_module

def main():
    with open('/home/user/app/encoded.dat', 'rb') as f:
        data = f.read()

    decoded = legacy_c_module.decode(data)

    with open('/home/user/app/decoded.txt', 'wb') as f:
        f.write(decoded)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
