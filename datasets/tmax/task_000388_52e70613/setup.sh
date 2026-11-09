#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create setup script to generate initial state
    cat << 'EOF' > /tmp/setup.py
import os
import gzip

os.makedirs('/home/user/incoming', exist_ok=True)

# Generate 1250 lines of text
lines = [f"Line {i:04d}: Legacy project log entry with special char: € é ñ\n" for i in range(1, 1251)]
full_text = "".join(lines)
encoded_data = full_text.encode('cp1252')

# Compress
compressed_data = gzip.compress(encoded_data)

# Split into roughly 3 parts
part_size = len(compressed_data) // 3
part_a = compressed_data[:part_size]
part_b = compressed_data[part_size:part_size*2]
part_c = compressed_data[part_size*2:]

with open('/home/user/incoming/chunk_a.gz', 'wb') as f: f.write(part_a)
with open('/home/user/incoming/chunk_b.gz', 'wb') as f: f.write(part_b)
with open('/home/user/incoming/chunk_c.gz', 'wb') as f: f.write(part_c)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
