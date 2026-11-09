#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo ffmpeg espeak-ng cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
import wave
import struct
import random

def create_wav(filename, sample_rate):
    with wave.open(filename, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        for _ in range(10):
            w.writeframes(struct.pack('<h', 0))

clean_rates = [8000, 16000, 44100, 48000]
evil_rates = [96000, 192000]

for i in range(50):
    create_wav(f'/app/corpus/clean/clean_{i}.wav', random.choice(clean_rates))
    create_wav(f'/app/corpus/evil/evil_{i}.wav', random.choice(evil_rates))
"

    espeak-ng -w /app/admin_voicemail.wav "Attention. To prevent storage exhaustion, our disk quota monitors must be protected. You must reject any wav file where the sample rate is strictly greater than forty eight thousand hertz."

    mkdir -p /home/user/scripts /home/user/logs
    cat << 'EOF' > /home/user/scripts/health_check.sh
#!/bin/bash
if [ -z "$LOG_DIR" ]; then
    echo "Error: LOG_DIR not set" >> /home/user/fallback.log
    exit 1
fi
echo "Health check passed" >> $LOG_DIR/health.log
EOF
    chmod +x /home/user/scripts/health_check.sh

    echo "* * * * * /home/user/scripts/health_check.sh" > /tmp/crontab
    crontab -u user /tmp/crontab

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
