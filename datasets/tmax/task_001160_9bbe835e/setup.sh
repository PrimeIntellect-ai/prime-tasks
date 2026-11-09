#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import gzip

def create_elf(e_machine):
    # Minimal ELF header
    # e_ident (16 bytes)
    elf = bytearray(b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00')
    # e_type (2), e_machine (2), e_version (4)
    elf += struct.pack('<HHI', 2, e_machine, 1)
    # Pad to 64 bytes for a valid header
    elf += b'\x00' * (64 - len(elf))
    return bytes(elf)

def create_pkg(filepath, path_str, elf_machine):
    elf_data = create_elf(elf_machine)
    gz_data = gzip.compress(elf_data)

    path_bytes = path_str.encode('utf-8')
    path_len = len(path_bytes)

    with open(filepath, 'wb') as f:
        f.write(b'PKG1')
        f.write(struct.pack('<B', path_len))
        f.write(path_bytes)
        f.write(struct.pack('<I', len(gz_data)))
        f.write(gz_data)

os.makedirs('/home/user/artifacts', exist_ok=True)

# Valid and under 100KB
create_pkg('/home/user/artifacts/good1.pkg', 'bin/server', 0x3E) # x86_64
create_pkg('/home/user/artifacts/good2.pkg', 'lib/module.so', 0x28) # ARM
create_pkg('/home/user/artifacts/bad1.pkg', '../../../etc/passwd', 0x3E) # Traversal
create_pkg('/home/user/artifacts/bad2.pkg', 'usr/bin/../lib/test', 0x03) # Traversal

# Over 100KB (must be ignored)
large_pkg_path = '/home/user/artifacts/large.pkg'
create_pkg(large_pkg_path, 'bin/ignore', 0x3E)
# Append junk to make it > 100KB
with open(large_pkg_path, 'ab') as f:
    f.write(b'\x00' * 105000)

# Wrong extension
create_pkg('/home/user/artifacts/wrong.txt', 'bin/wrong', 0x3E)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
