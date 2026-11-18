#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    # Create the certificate with CN=DevSecOps_Trust
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/policy.key -out /home/user/policy.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=DevSecOps_Trust" 2>/dev/null

    # Generate the payload
    python3 -c '
import base64
plaintext = b"POLICY=DENY_UNTRUSTED_REGISTRIES"
key = b"DevSecOps_Trust"
ciphertext = bytearray()
for i in range(len(plaintext)):
    ciphertext.append(plaintext[i] ^ key[i % len(key)])
with open("/home/user/payload.txt", "w") as f:
    f.write(base64.b64encode(ciphertext).decode("utf-8"))
'

    chmod -R 777 /home/user
