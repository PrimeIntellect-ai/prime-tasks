#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Python script to generate ARTF files
    cat << 'EOF' > /tmp/gen_artf.py
import struct

def create_entry(path, entry_type, data):
    path_bytes = path.encode('utf-8')
    data_bytes = data if isinstance(data, bytes) else data.encode('utf-8')
    return struct.pack('<H', len(path_bytes)) + path_bytes + struct.pack('B', entry_type) + struct.pack('<I', len(data_bytes)) + data_bytes

def write_artf(filename, entries):
    with open(filename, 'wb') as f:
        f.write(b'ARTF')
        for entry in entries:
            f.write(entry)

# Clean 1
write_artf('/app/corpus/clean/clean1.artf', [
    create_entry('file.txt', 0, b'hello'),
    create_entry('link.txt', 1, b'file.txt')
])

# Clean 2
write_artf('/app/corpus/clean/clean2.artf', [
    create_entry('dir/data.bin', 0, b'data')
])

# Evil 1
write_artf('/app/corpus/evil/evil_abs.artf', [
    create_entry('/etc/passwd', 0, b'hack')
])

# Evil 2
write_artf('/app/corpus/evil/evil_trav.artf', [
    create_entry('../../../tmp/hack', 0, b'hack')
])

# Evil 3
write_artf('/app/corpus/evil/evil_sym_loop.artf', [
    create_entry('loop_dir', 1, b'.')
])
EOF

    python3 /tmp/gen_artf.py

    # Create dummy extractor binary
    cat << 'EOF' > /tmp/extractor.c
#include <stdio.h>
int main() {
    return 0;
}
EOF
    gcc -s /tmp/extractor.c -o /app/extractor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
