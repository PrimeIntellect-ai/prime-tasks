#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create the binary with the hardcoded key
    cat << 'EOF' > auth_service.c
#include <stdio.h>
int main() {
    const char* key = "SECRET_AUTH_KEY_8f92bA";
    printf("Starting auth service...\n");
    return 0;
}
EOF
    gcc auth_service.c -o auth_service
    rm auth_service.c

    # 2. Create the memdump with the deleted python script
    head -c 1024 /dev/urandom > memdump.bin
    cat << 'EOF' >> memdump.bin
# BEGIN PARSER
import sys

def decode(filepath, key):
    with open(filepath, 'rb') as f:
        data = f.read()

    # Fails if non-ASCII bytes are present
    try:
        text = data.decode('ascii')
    except UnicodeDecodeError:
        print("ERROR: Input data corrupted. Non-ASCII bytes detected.")
        sys.exit(1)

    res = []
    for i, c in enumerate(text):
        res.append(chr(ord(c) ^ ord(key[i % len(key)])))
    print("".join(res))

if __name__ == "__main__":
    decode(sys.argv[1], sys.argv[2])
# END PARSER
EOF
    head -c 1024 /dev/urandom >> memdump.bin

    # 3. Create the corrupted events.dat
    cat << 'EOF' > generate_event.py
target = "CRITICAL_FAILURE_AT_NODE_77"
key = "SECRET_AUTH_KEY_8f92bA"
res = []
for i, c in enumerate(target):
    res.append(chr(ord(c) ^ ord(key[i % len(key)])))

with open("events.dat", "wb") as f:
    # Write corrupted junk (non-ascii)
    f.write(b'\xDE\xAD\xBE\xEF\x88\x99')
    # Write the encoded payload
    f.write("".join(res).encode('ascii'))
EOF
    python3 generate_event.py
    rm generate_event.py

    chmod +x auth_service

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
