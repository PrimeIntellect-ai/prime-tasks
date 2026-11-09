#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_bin.py
import struct
import zlib

def make_record(svc_id, ver, dep, min_ver):
    b = struct.pack('<BB', svc_id, len(ver)) + ver.encode('ascii')
    if dep == 0xFF:
        b += struct.pack('<BB', 0xFF, 0)
    else:
        b += struct.pack('<BB', dep, len(min_ver)) + min_ver.encode('ascii')
    return b

payload = b'DPLY' + struct.pack('<H', 7)
payload += make_record(1, "2.0.0", 0xFF, "")
payload += make_record(2, "1.5.0", 1, "1.0.0")
payload += make_record(3, "1.0.0", 4, "1.0.0")
payload += make_record(4, "0.9.0", 0xFF, "")
payload += make_record(5, "3.1.2", 2, "2.0.0")
payload += make_record(6, "1.1.0", 3, "1.0.0")
payload += make_record(7, "4.0.0", 8, "1.0.0")

adler = zlib.adler32(payload) & 0xffffffff
payload += struct.pack('<I', adler)

with open('/home/user/deploy.bin', 'wb') as f:
    f.write(payload)
EOF

    python3 /tmp/generate_bin.py
    rm /tmp/generate_bin.py

    chmod -R 777 /home/user
