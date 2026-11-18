#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    # Create a mock ELF binary by copying an existing system binary and injecting the IP address
    cp /bin/ls /home/user/evidence/telemetry_svc
    echo -ne '\x00\x00\x00\x00203.0.113.85\x00\x00\x00\x00' >> /home/user/evidence/telemetry_svc
    chmod +x /home/user/evidence/telemetry_svc

    # Create the encrypted audit log
    python3 -c '
plaintext = b"[AUDIT_START] Server compliance check passed. Token: COMPLIANCE-8821-XRT.\n"
key = 0x4B
ciphertext = bytes([b ^ key for b in plaintext])
with open("/home/user/evidence/audit_log.enc", "wb") as f:
    f.write(ciphertext)
'

    chown -R user:user /home/user/evidence
    chmod -R 777 /home/user
