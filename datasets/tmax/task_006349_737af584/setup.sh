#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

python3 -c '
import os
import itertools

# Create access.log
log_content = """10.0.0.5 - - [14/Oct/2023:10:00:01 +0000] "GET /index.html HTTP/1.1" 200 1024
10.0.0.6 - - [14/Oct/2023:10:05:12 +0000] "GET /login HTTP/1.1" 200 512
192.168.100.42 - - [14/Oct/2023:10:15:30 +0000] "GET /login?next=http://evil.corp/malware HTTP/1.1" 302 0
10.0.0.7 - - [14/Oct/2023:10:20:45 +0000] "GET /about HTTP/1.1" 200 2048
"""
with open("/home/user/access.log", "w") as f:
    f.write(log_content)

# Create suspicious_bin (Fake ELF with embedded key)
elf_header = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"
binary_padding = os.urandom(128)
key_string = b"KEY:X0rS3cr3t"
trailer = os.urandom(64)

with open("/home/user/suspicious_bin", "wb") as f:
    f.write(elf_header + binary_padding + key_string + b"\x00" + trailer)
os.chmod("/home/user/suspicious_bin", 0o755)

# Create stolen_data.enc
plaintext = b"CONFIDENTIAL_FINANCIAL_DATA_Q3_2023"
key = b"X0rS3cr3t"

ciphertext = bytearray()
for p, k in zip(plaintext, itertools.cycle(key)):
    ciphertext.append(p ^ k)

with open("/home/user/stolen_data.enc", "wb") as f:
    f.write(ciphertext)
'

chmod -R 777 /home/user
