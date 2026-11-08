#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget tar
    pip3 install pytest

    # Create /app and download bzip2
    mkdir -p /app
    cd /app
    wget https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
    tar -xzf bzip2-1.0.8.tar.gz
    rm bzip2-1.0.8.tar.gz
    cd bzip2-1.0.8
    sed -i 's/^CC=gcc/CC=false/' Makefile

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/journal_compiler_oracle
#!/usr/bin/env python3
import sys
import bz2
import struct

def escape(s):
    return s.replace("'", "'\\''")

def read_cstr(data, offset):
    end = data.find(b'\x00', offset)
    if end == -1:
        return None, offset
    s = data[offset:end].decode('ascii', errors='ignore')
    return s, end + 1

def main():
    compressed_data = sys.stdin.buffer.read()
    if not compressed_data:
        return
    try:
        data = bz2.decompress(compressed_data)
    except Exception:
        sys.exit(1)

    offset = 0
    length = len(data)

    while offset < length:
        opcode = data[offset]
        offset += 1

        if opcode == 0x00:
            if offset + 2 > length: break
            n = struct.unpack_from('<H', data, offset)[0]
            offset += 2
            for _ in range(n):
                old_name, offset = read_cstr(data, offset)
                new_name, offset = read_cstr(data, offset)
                print(f"mv '{escape(old_name)}' '{escape(new_name)}'")
        elif opcode == 0x01:
            target, offset = read_cstr(data, offset)
            link_name, offset = read_cstr(data, offset)
            print(f"ln '{escape(target)}' '{escape(link_name)}'")
        elif opcode == 0x02:
            target, offset = read_cstr(data, offset)
            link_name, offset = read_cstr(data, offset)
            print(f"ln -s '{escape(target)}' '{escape(link_name)}'")
        else:
            break

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/oracle/journal_compiler_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
