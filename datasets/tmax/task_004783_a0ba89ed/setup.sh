#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import struct

# Create the binary data file
with open('/home/user/sensor_data.bin', 'wb') as f:
    # Header: Magic number (0xDEADBEEF) and count (5)
    f.write(struct.pack('<II', 0xDEADBEEF, 5))

    # 5 Unsigned 32-bit integers
    f.write(struct.pack('<I', 3000000000))
    f.write(struct.pack('<I', 2000000000))
    f.write(struct.pack('<I', 4000000000))
    f.write(struct.pack('<I', 1500000000))
    f.write(struct.pack('<I', 3500000000))

# Create the buggy script
script_content = """import struct
import sys

def process_data(file_path):
    total = 0
    with open(file_path, 'rb') as f:
        header = f.read(8)
        if len(header) < 8:
            return 0
        magic, count = struct.unpack('<II', header)
        if magic != 0xDEADBEEF:
            print("Invalid magic number")
            return None

        for _ in range(count):
            chunk = f.read(4)
            if len(chunk) < 4:
                break
            # Bug: reading as signed integer instead of unsigned
            value = struct.unpack('<i', chunk)[0]
            total += value
    return total

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python calculate_sum.py <file>")
        sys.exit(1)
    print(process_data(sys.argv[1]))
"""

with open('/home/user/calculate_sum.py', 'w') as f:
    f.write(script_content)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
