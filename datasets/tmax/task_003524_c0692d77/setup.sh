#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make tar gzip
    pip3 install pytest

    mkdir -p /app

    # Create settings.ini and archive it
    cat << 'EOF' > /app/settings.ini
[Audio]
amplitude_threshold=150
min_silence_duration_ms=500
EOF
    tar -czf /app/config_data.tar.gz -C /app settings.ini
    rm /app/settings.ini

    # Generate a dummy valid WAV file (16-bit PCM Mono)
    python3 -c "
import wave, struct, math
sample_rate = 16000
duration = 10
obj = wave.open('/app/voicemail.wav','w')
obj.setnchannels(1)
obj.setsampwidth(2)
obj.setframerate(sample_rate)
for i in range(sample_rate * duration):
    if (i // sample_rate) % 2 == 0:
        value = int(10000 * math.sin(2 * math.pi * 440 * (i / sample_rate)))
    else:
        value = 0
    data = struct.pack('<h', value)
    obj.writeframesraw(data)
obj.close()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
