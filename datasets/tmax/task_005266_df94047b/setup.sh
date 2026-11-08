#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import struct

records = [
    # magic, ts, lat, lon
    (0xDEADBEEF, 100, 37.7749, -122.4194),
    (0xDEADBEEF, 101, 34.0522, -118.2437),
    (0x00000000, 102, 0.0, 0.0), # Corrupted
    (0xDEADBEEF, 103, 40.7128, -74.0060),
    (0xDEADBEEF, 104, 51.5074, -0.1278),
    (0x12345678, 105, 0.0, 0.0), # Corrupted
    (0xDEADBEEF, 106, 48.8566, 2.3522),
    (0xDEADBEEF, 107, 35.6895, 139.6917),
    (0xDEADBEEF, 108, -33.8688, 151.2093),
    (0xDEADBEEF, 109, 55.7558, 37.6173),
    (0xDEADBEEF, 110, -23.5505, -46.6333),
    (0xDEADBEEF, 111, -37.8136, 144.9631),
]

with open('/home/user/sensor_data.bin', 'wb') as f:
    for magic, ts, lat, lon in records:
        f.write(struct.pack('<I I d d', magic, ts, lat, lon))
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    cat << 'EOF' > /home/user/process.py
import struct
import multiprocessing
import os

def process_chunk(offset):
    with open('/home/user/sensor_data.bin', 'rb') as f:
        f.seek(offset)
        data = f.read(24)
        if len(data) < 24: return

        # BUG 1: Unpacking 64-bit floats as 32-bit (and ignoring the rest)
        magic, ts, lat, lon = struct.unpack('<I I f f 8x', data)

        if magic != 0xDEADBEEF:
            return # Skip corrupted

        # BUG 2: Race condition writing to file
        with open('/home/user/output.txt', 'a') as out:
            out.write(f"Timestamp: {ts}, Lat: {lat:.4f}, Lon: {lon:.4f}\n")

if __name__ == '__main__':
    file_size = os.path.getsize('/home/user/sensor_data.bin')
    offsets = range(0, file_size, 24)

    # Clear output file
    open('/home/user/output.txt', 'w').close()

    with multiprocessing.Pool(4) as p:
        p.map(process_chunk, offsets)
EOF

    chmod +x /home/user/process.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
