#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/delta_apply.py
import sys
import struct

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    with open(sys.argv[1], 'rb') as f:
        base = f.read()
    with open(sys.argv[2], 'rb') as f:
        delta = f.read()

    if delta[:4] != b'DLTA':
        sys.exit(1)

    out = b''
    pos = 4
    while pos < len(delta):
        op = delta[pos]
        pos += 1
        if op == 1:
            offset, length = struct.unpack('<II', delta[pos:pos+8])
            pos += 8
            out += base[offset:offset+length]
        elif op == 2:
            length, = struct.unpack('<I', delta[pos:pos+4])
            pos += 4
            out += delta[pos:pos+length]
            pos += length
        elif op == 3:
            val = delta[pos:pos+1]
            pos += 1
            length, = struct.unpack('<I', delta[pos:pos+4])
            pos += 4
            out += val * length
        else:
            sys.exit(1)
    sys.stdout.buffer.write(out)

if __name__ == '__main__':
    main()
EOF

    cd /tmp
    pyinstaller --onefile delta_apply.py
    cp dist/delta_apply /app/delta_apply
    strip /app/delta_apply
    chmod +x /app/delta_apply
    rm -rf /tmp/delta_apply.py /tmp/build /tmp/dist /tmp/delta_apply.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
