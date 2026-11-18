#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app /home/user/spool

    cat << 'EOF' > /app/storage_decode.c
#include <stdio.h>
int main() {
    int c;
    while ((c = getchar()) != EOF) {
        putchar(c ^ 0x55);
    }
    return 0;
}
EOF
    gcc -O2 /app/storage_decode.c -o /app/storage_decode
    strip -s /app/storage_decode
    chmod +x /app/storage_decode
    rm /app/storage_decode.c

    python3 -c '
import struct, json
def make_file(path, vol, used, free):
    payload = json.dumps({"volume_id": vol, "used_bytes": used, "free_bytes": free, "inode_usage": 0.5}).encode("utf-8")
    binary_data = struct.pack(">I", 0xDEADC0DE) + struct.pack(">I", len(payload)) + payload
    enc_data = bytes([b ^ 0x55 for b in binary_data])
    with open(path, "wb") as f:
        f.write(enc_data)

make_file("/home/user/spool/snap1.enc", "vol-X1", 1000, 3000) # 25.0%
make_file("/home/user/spool/snap2.enc", "vol-Y2", 5000, 5000) # 50.0%
'

    chown -R user:user /home/user/spool
    chmod -R 777 /home/user
