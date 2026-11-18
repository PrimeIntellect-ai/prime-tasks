#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voice_memo.wav "forty two"

    cat << 'EOF' > /app/oracle_extract
#!/usr/bin/env python3
import sys
import struct
import fcntl

def main():
    if len(sys.argv) < 3:
        sys.exit(0)
    archive_file = sys.argv[1]
    lock_file = sys.argv[2]

    try:
        f = open(lock_file, 'w')
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except Exception:
        sys.stdout.write("LOCKED")
        sys.exit(0)

    try:
        with open(archive_file, 'rb') as af:
            data = af.read()
    except Exception:
        sys.exit(0)

    if len(data) < 2:
        sys.exit(0)

    try:
        num_entries = struct.unpack_from('<H', data, 0)[0]
    except Exception:
        sys.exit(0)

    offset = 2

    for _ in range(num_entries):
        if offset >= len(data):
            break
        name_len = data[offset]
        offset += 1

        if offset + name_len > len(data):
            break
        try:
            name = data[offset:offset+name_len].decode('ascii')
        except Exception:
            name = ""
        offset += name_len

        if offset + 4 > len(data):
            break
        comp_len = struct.unpack_from('<I', data, offset)[0]
        offset += 4

        if offset + comp_len > len(data):
            break

        comp_data = data[offset:offset+comp_len]
        offset += comp_len

        if '../' in name or name.startswith('/'):
            continue

        decrypted = bytes([b ^ 42 for b in comp_data])
        try:
            text = decrypted.decode('utf-16le')
            sys.stdout.buffer.write(text.encode('utf-8'))
        except Exception:
            pass

    sys.stdout.flush()

if __name__ == '__main__':
    main()
EOF

    chmod +x /app/oracle_extract

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
