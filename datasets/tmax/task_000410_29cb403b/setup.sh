#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyinstaller

    # Create the vendored package directory structure
    mkdir -p /app/cred-rotator/rotator
    mkdir -p /app/cred-rotator/bin

    # Create the vulnerable cli.py
    cat << 'EOF' > /app/cred-rotator/rotator/cli.py
import subprocess

def rotate_credentials(master_key):
    # Vulnerable implementation: passing master_key as a command-line argument
    result = subprocess.run(
        ['/app/cred-rotator/bin/generate_key.sh', master_key],
        capture_output=True,
        text=True
    )
    return result.stdout.strip()
EOF

    # Create the vulnerable generate_key.sh
    cat << 'EOF' > /app/cred-rotator/bin/generate_key.sh
#!/bin/bash
# Vulnerable: reads master key from $1
MASTER_KEY=$1
if [ -z "$MASTER_KEY" ]; then
    echo "Error: Master key not provided"
    exit 1
fi
# Simulate key generation
echo "rotated_key_based_on_${MASTER_KEY}"
EOF
    chmod +x /app/cred-rotator/bin/generate_key.sh

    # Create __init__.py and setup.py for the package
    touch /app/cred-rotator/rotator/__init__.py
    cat << 'EOF' > /app/cred-rotator/setup.py
from setuptools import setup, find_packages

setup(
    name='cred-rotator',
    version='1.2.0',
    packages=find_packages(),
)
EOF

    # Create the reference oracle using PyInstaller to simulate a stripped binary
    cat << 'EOF' > /tmp/oracle.py
import sys
import hashlib

def generate_token(session_id, client_ip):
    data = f"{session_id}|{client_ip}".encode('utf-8')
    h = hashlib.sha256(data).digest()
    first_half = h[:16]
    second_half = h[16:]
    xor_result = bytes(a ^ b for a, b in zip(first_half, second_half))
    final_hash = xor_result + second_half
    return final_hash.hex()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)
    print(generate_token(sys.argv[1], sys.argv[2]), end="")
EOF

    cd /tmp
    pyinstaller --onefile oracle.py
    mkdir -p /opt/oracles
    cp dist/oracle /opt/oracles/token_oracle
    chmod +x /opt/oracles/token_oracle

    # Cleanup build artifacts
    rm -rf /tmp/oracle.py /tmp/build /tmp/dist /tmp/oracle.spec

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
