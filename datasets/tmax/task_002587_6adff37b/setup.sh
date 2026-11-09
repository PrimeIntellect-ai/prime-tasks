#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak openssh-client curl
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/intercepted.wav "eight four two six zero one"

    useradd -m -s /bin/bash user || true

    python3 -c '
import binascii
plaintext = "CONFIDENTIAL: OPERATION_RED_DAWN_TARGET_ACQUIRED"
pin = "842601"
ciphertext = bytearray()
for i in range(len(plaintext)):
    ciphertext.append(ord(plaintext[i]) ^ ord(pin[i % len(pin)]))
with open("/home/user/traffic.enc", "w") as f:
    f.write(binascii.hexlify(ciphertext).decode("utf-8"))
'

    chmod -R 777 /home/user
