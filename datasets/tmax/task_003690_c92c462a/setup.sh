#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/tools

    # Generate signal.wav
    espeak -w /app/signal.wav "The authentication pin is eight two five one."

    # Create malware.dmp
    echo -n "XOR_KEY_SIG=A7B2C9D4" > /app/malware.dmp
    dd if=/dev/urandom bs=1024 count=10 >> /app/malware.dmp

    # Create requirements.txt
    cat << 'EOF' > /app/tools/requirements.txt
numpy==1.21.0
scipy==1.7.3
librosa>=0.10.0
EOF

    # Create oracle_decoder
    cat << 'EOF' > /app/oracle_decoder
#!/usr/bin/env python3
import sys
import wave
import struct

def decode(wav_path, pin):
    with wave.open(wav_path, 'rb') as w:
        data = w.readframes(256)

    frames = struct.unpack('<256h', data)
    bits = [frame & 1 for frame in frames]

    packed_bytes = bytearray(32)
    for i in range(32):
        byte_val = 0
        for j in range(8):
            byte_val = (byte_val << 1) | bits[i * 8 + j]
        packed_bytes[i] = byte_val

    xor_key = bytes.fromhex('A7B2C9D4')
    for i in range(32):
        packed_bytes[i] ^= xor_key[i % 4]

    pin_int = int(pin)
    pin_bytes = struct.pack('>I', pin_int)
    for i in range(32):
        packed_bytes[i] ^= pin_bytes[i % 4]

    print(packed_bytes.hex())

if __name__ == '__main__':
    decode(sys.argv[1], sys.argv[2])
EOF
    chmod +x /app/oracle_decoder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
