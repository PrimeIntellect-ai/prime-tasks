#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 bc gawk
    pip3 install pytest

    mkdir -p /app/data /app/evidence

    # Create dummy suspicious binary
    cat << 'EOF' > /app/suspicious_audio_processor
#!/bin/bash
echo "Error: Precision loss detected"
EOF
    chmod +x /app/suspicious_audio_processor

    # Create oracle processor
    cat << 'EOF' > /app/oracle_processor
#!/bin/bash
awk -v f="$1" -v t="$2" 'BEGIN { printf "%.6f\n", sqrt(f/t) }'
EOF
    chmod +x /app/oracle_processor

    # Create SQLite database and corrupt header
    sqlite3 /app/data/telemetry.db "CREATE TABLE audio_metadata(id INTEGER, threshold REAL); INSERT INTO audio_metadata VALUES(1, 0.005);"
    dd if=/dev/urandom of=/app/data/telemetry.db bs=1 count=16 conv=notrunc

    # Create audio file with Python
    cat << 'EOF' > /tmp/make_audio.py
import wave, struct, math
sample_rate = 44100
duration = 1.0
tones = [852, 1209, 1477]
with wave.open('/app/evidence/payload.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    for i in range(int(sample_rate * duration)):
        val = sum(math.sin(2 * math.pi * t * i / sample_rate) for t in tones) / len(tones)
        f.writeframes(struct.pack('h', int(val * 32767.0)))
EOF
    python3 /tmp/make_audio.py
    rm /tmp/make_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
