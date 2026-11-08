#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest pytesseract pillow pexpect

    mkdir -p /app
    mkdir -p /home/user

    # Create the image with specs
    convert -pointsize 32 label:"Username: omega_admin\nStartPort: 7000\nRotateSize: 100M" /app/provision_specs.png

    # Create the legacy installer script
    cat << 'EOF' > /app/legacy_installer.py
#!/usr/bin/env python3
import sys
import time

if len(sys.argv) != 2:
    print("Usage: legacy_installer.py <instance_id>")
    sys.exit(1)

instance_id = sys.argv[1]
print("Starting interactive installer...")
sys.stdout.flush()
time.sleep(1.0)
print("Enter Admin Username: ", end="")
sys.stdout.flush()
user = sys.stdin.readline().strip()
time.sleep(0.5)
print("Enter Service Port: ", end="")
sys.stdout.flush()
port = sys.stdin.readline().strip()
time.sleep(0.5)

# Create a dummy log to prove it ran
with open(f"/home/user/logs/service_{instance_id}.log", "w") as f:
    f.write(f"Provisioned instance {instance_id} for {user} on port {port}\n")
EOF
    chmod +x /app/legacy_installer.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
