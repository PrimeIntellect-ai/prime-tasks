#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Create a dummy WAV file
    python3 -c "
import wave, struct, math
with wave.open('/app/call_record_001.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(16000)
    for i in range(16000 * 5):
        value = int(32767.0 * math.cos(2 * math.pi * 440.0 * i / 16000.0))
        f.writeframesraw(struct.pack('<h', value))
"

    # Create the segments file
    cat << 'EOF' > /app/call_001_segments.txt
0.00	2.00	SPEECH
2.00	3.00	HOLD_MUSIC
3.00	5.00	SPEECH
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
