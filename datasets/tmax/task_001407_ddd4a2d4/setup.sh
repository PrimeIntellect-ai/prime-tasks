#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ systemd dbus dbus-user-session
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_wav.py
import wave
import struct
import math

with wave.open('/app/input.wav', 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    # 1 second of 440Hz sine wave
    samples = [int(32767 * math.sin(2 * math.pi * 440 * i / 44100)) for i in range(44100)]
    data = struct.pack(f'<{len(samples)}h', *samples)
    w.writeframes(data)
EOF
    python3 /tmp/gen_wav.py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/analyzer.cpp
#include <iostream>

int main(int argc, char** argv) {
    // TODO: implement analyzer
    return 0;
}
EOF

    chmod -R 777 /home/user
