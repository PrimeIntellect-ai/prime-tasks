#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    # Create directories
    mkdir -p /app/audio /app/src /opt/libcore-2.1.0 /opt/libnet-1.4.2

    # Generate telemetry.wav
    python3 -c "
import wave
import struct

data = 'libcore-2.1.0 libnet-1.4.2'
samples = []

for char in data:
    val = ord(char)
    nibbles = [(val >> 4) & 0xF, val & 0xF]
    for nibble in nibbles:
        d1 = (nibble >> 3) & 1
        d2 = (nibble >> 2) & 1
        d3 = (nibble >> 1) & 1
        d4 = nibble & 1

        p1 = d1 ^ d2 ^ d3
        p2 = d2 ^ d3 ^ d4
        p3 = d1 ^ d3 ^ d4
        p4 = d1 ^ d2 ^ d4

        bits = [d1, d2, d3, d4, p1, p2, p3, p4]
        for b in bits:
            if b == 1:
                samples.extend([10000] * 8)
            else:
                samples.extend([0] * 8)

with wave.open('/app/audio/telemetry.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(8000)
    for s in samples:
        f.writeframes(struct.pack('<h', s))
"

    # Create Makefile
    cat << 'EOF' > /app/src/Makefile
all: main

main: main.c
	gcc -o main main.c -L/opt/libcore-1.0.0 -lcore -L/opt/libnet-1.0.0 -lnet
EOF

    # Create main.c
    cat << 'EOF' > /app/src/main.c
int main() {
    return 0;
}
EOF

    # Create dummy libraries
    gcc -shared -o /opt/libcore-2.1.0/libcore.so -x c /dev/null
    gcc -shared -o /opt/libnet-1.4.2/libnet.so -x c /dev/null

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
