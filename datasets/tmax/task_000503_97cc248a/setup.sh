#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc cargo espeak
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the audio file using espeak (fast and minimal)
    espeak -w /app/voicemail.wav "We successfully backdoored the upload service. The file paths are obfuscated using a repeating XOR cipher. The eight byte key is exported in the ELF symbol table as CUSTOM_XOR_KEY. Write a Rust detector to verify payloads."

    # Create the ELF binary with the exported key
    cat << 'EOF' > /tmp/upload_handler.c
#include <stdio.h>

const unsigned char CUSTOM_XOR_KEY[8] = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE};

int main() {
    printf("Upload handler running...\n");
    return 0;
}
EOF
    gcc -o /app/upload_handler /tmp/upload_handler.c

    # Generate the adversarial corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import os

key = bytes([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])

def xor_encode(text):
    return bytes([text[i] ^ key[i % len(key)] for i in range(len(text))])

clean_paths = [
    "image.png", 
    "document.pdf", 
    "archive.tar.gz", 
    "script.js", 
    "style.css",
    "users/profile.jpg"
]

evil_paths = [
    "../../../etc/passwd", 
    "/var/log/syslog", 
    "../../../root/.ssh/id_rsa", 
    "/etc/shadow", 
    "../config.yml",
    "/bin/bash"
]

for i, p in enumerate(clean_paths):
    with open(f"/app/corpus/clean/file_{i}.bin", "wb") as f:
        f.write(xor_encode(p.encode()))

for i, p in enumerate(evil_paths):
    with open(f"/app/corpus/evil/file_{i}.bin", "wb") as f:
        f.write(xor_encode(p.encode()))
EOF
    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
