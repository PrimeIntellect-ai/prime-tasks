#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import struct
import os

def rle_compress(data):
    compressed = bytearray()
    if not data:
        compressed.extend([0, 0])
        return compressed

    i = 0
    while i < len(data):
        char = data[i]
        count = 1
        while i + 1 < len(data) and data[i + 1] == char and count < 255:
            count += 1
            i += 1
        compressed.extend([count, char])
        i += 1
    compressed.extend([0, 0]) # EOF marker
    return compressed

def create_slog(filename, files):
    with open(filename, 'wb') as f:
        f.write(b'SLOG')
        f.write(struct.pack('<I', len(files)))
        for name, data in files:
            name_bytes = name.encode('ascii')
            f.write(struct.pack('<H', len(name_bytes)))
            f.write(name_bytes)
            f.write(rle_compress(data))

log1 = b"""[2023-10-25 10:00:00] INFO Server started.
Loading modules...
Done.
[2023-10-25 10:05:00] ERROR Disk usage high.
CRITICAL_SPACE_ERROR: Partition /dev/sda1 is at 99%.
Please clean up old logs immediately.
[2023-10-25 10:06:00] INFO Routine cleanup initiated.
"""

log2 = b"""[2023-10-26 11:00:00] INFO User login.
[2023-10-26 11:15:00] WARNING Memory usage spike.
[2023-10-26 11:20:00] ERROR Another disk error.
CRITICAL_SPACE_ERROR: Failed to write to database.
Check storage backend.
[2023-10-26 11:25:00] INFO Retry successful.
"""

malicious1 = b"root:x:0:0:root:/root:/bin/bash\n"
malicious2 = b"alias ls='rm -rf /'\n"

files = [
    ("valid_log_A.txt", log1),
    ("../../../etc/passwd", malicious1),
    ("/home/user/.bashrc_override", malicious2),
    ("valid_log_B.txt", log2)
]

os.makedirs("/home/user", exist_ok=True)
create_slog("/home/user/server_logs.slog", files)

with open("/home/user/slog_config.ini", "w") as f:
    f.write("extract_dir=/home/user/extracted\nquarantine_log=/home/user/quarantine.log\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
