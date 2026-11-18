#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/math_service
    cd /home/user/math_service

    git init
    git config --global user.email "admin@example.com"
    git config --global user.name "Admin"

    cat << 'EOF' > secret.key
XOR_KEY=42
EOF
    git add secret.key
    git commit -m "Initial commit with secret key"

    rm secret.key
    git add -u
    git commit -m "Remove secret key"

    python3 -c '
lines = [str(x**2) for x in range(1, 101)]
lines.insert(50, "CORRUPTED_DATA_DROP")
data = "\n".join(lines)
key = 42
encrypted = bytearray([b ^ key for b in data.encode()])
with open("data.enc", "wb") as f:
    f.write(encrypted)
'

    cat << 'EOF' > integrate.py
import sys

def load_data(filename, key):
    with open(filename, "rb") as f:
        encrypted = f.read()
    decrypted = bytearray([b ^ key for b in encrypted]).decode()
    data = []
    for line in decrypted.split('\n'):
        if not line.strip(): continue
        data.append(float(line)) # Agent needs to add try-except here
    return data

def compute_integral(data, dx=1.0):
    total = 0.0
    # Agent needs to change len(data) - 2 to len(data) - 1
    for i in range(len(data) - 2):
        total += (data[i] + data[i+1]) / 2.0 * dx
    return total

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 integrate.py <data_file> <key>")
        sys.exit(1)

    key = int(sys.argv[2])
    data = load_data(sys.argv[1], key)
    res = compute_integral(data)
    print(res)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
