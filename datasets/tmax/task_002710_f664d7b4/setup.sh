#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libseccomp-dev binutils cppcheck openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Generate Root CA
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout rootCA.key -out rootCA.pem -subj "/CN=RootCA"

    # Generate Valid Cert
    openssl req -newkey rsa:2048 -nodes -keyout valid.key -out valid.csr -subj "/CN=Valid"
    openssl x509 -req -in valid.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out valid.pem -days 365

    # Generate Invalid Cert
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout invalid.key -out invalid.pem -subj "/CN=Invalid"

    # Create binary dump
    python3 -c '
import struct
payload1 = b"User info: 1234567812345678, SSN: 123-45-6789."
with open("valid.pem", "rb") as f:
    payload2 = f.read()
with open("invalid.pem", "rb") as f:
    payload3 = f.read()

with open("dump.bin", "wb") as f:
    f.write(struct.pack("<HH", 1, len(payload1)) + payload1)
    f.write(struct.pack("<HH", 2, len(payload2)) + payload2)
    f.write(struct.pack("<HH", 3, len(payload3)) + payload3)
'

    # Create object file and embed dump
    echo "int dummy() { return 0; }" > empty.c
    gcc -c empty.c -o empty.o
    objcopy --add-section .traffic_dump=dump.bin empty.o capture.o

    # Cleanup
    rm -f empty.c empty.o dump.bin valid.key valid.csr valid.pem invalid.key invalid.pem rootCA.key rootCA.srl

    chmod -R 777 /home/user
