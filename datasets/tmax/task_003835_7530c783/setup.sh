#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the voicemail.wav
    espeak -w /app/voicemail.wav "Hey, I am losing connection. The database is down. You need to immediately reconstruct the edges for node ID eight three seven four. I repeat, node ID 8374. Use the binary dump."

    # Generate the graph_backup.bin
    python3 -c "
import struct
with open('/app/graph_backup.bin', 'wb') as f:
    # Noise record
    f.write(struct.pack('<IIII', 1234, 2, 555, 666))
    # Target record
    f.write(struct.pack('<IIIII', 8374, 3, 1020, 45, 9991))
    # Noise record
    f.write(struct.pack('<III', 9999, 1, 111))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
