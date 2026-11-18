#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/recording.wav "The server crashed at midnight. It reported ERR-9910. After rebooting, we saw SYS-0042 and then another ERR-9910. The network interface dropped with NET-4431."

    python3 -c "
import os
os.makedirs('/app', exist_ok=True)
with open('/app/legacy_logs.bin', 'wb') as f:
    f.write(b'Starting log dump...\n')
    f.write('DBA-1100 encountered.\n'.encode('utf-8'))
    f.write(b'\xff\xfe\x00\x00')
    f.write('Alert SYS-0042 repeated.\n'.encode('utf-16le'))
    f.write(b'\x80\x81')
    f.write('Final code SEC-8812.\n'.encode('utf-8'))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
