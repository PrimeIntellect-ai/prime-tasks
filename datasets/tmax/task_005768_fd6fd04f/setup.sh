#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils golang-go
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the raw XOR key (4 bytes)
    echo -n -e "\x7a\x8b\x9c\x4d" > /tmp/raw_key.bin

    # Create the plaintext HTTP traffic payload
    cat << 'EOF' > /tmp/payload.txt
POST /beacon/init HTTP/1.1
Host: malicious-c2.local
X-Beacon-Auth: token_admin_9912
Content-Length: 15

alive=true&os=lx
GET /beacon/tasks HTTP/1.1
Host: malicious-c2.local
X-Beacon-Auth: token_user_7734
Content-Length: 0

EOF

    # XOR encrypt the payload using Python
    python3 -c '
key = b"\x7a\x8b\x9c\x4d"
with open("/tmp/payload.txt", "rb") as f:
    data = f.read()
res = bytes(data[i] ^ key[i % len(key)] for i in range(len(data)))
with open("/home/user/payload.enc", "wb") as f:
    f.write(res)
'

    # Create the dummy binary and inject the key section
    cat << 'EOF' > /tmp/dummy.c
int main() { return 0; }
EOF
    gcc /tmp/dummy.c -o /home/user/malware.bin
    objcopy --add-section .malware_key=/tmp/raw_key.bin /home/user/malware.bin

    # Cleanup
    rm /tmp/raw_key.bin /tmp/payload.txt /tmp/dummy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
