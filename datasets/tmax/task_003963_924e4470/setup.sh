#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest gTTS

mkdir -p /app/dataset/logs/2024/01 /app/dataset/logs/2024/02

cat << 'EOF' > /app/dataset/logs/2024/01/sensor_a.log
---BEGIN RECORD---
Timestamp: 2024-01-10T14:22:01Z
SensorID: A1
Reading: 45.2
AnomalyFlag: FALSE
---END RECORD---
---BEGIN RECORD---
Timestamp: 2024-01-15T09:11:00Z
SensorID: A1
Reading: 99.9
AnomalyFlag: TRUE
---END RECORD---
EOF

cat << 'EOF' > /app/dataset/logs/2024/01/sensor_b.log
---BEGIN RECORD---
Timestamp: 2024-01-05T08:30:00Z
SensorID: B1
Reading: 105.4
AnomalyFlag: TRUE
---END RECORD---
EOF

touch /app/dataset/logs/2024/02/sensor_a.log

gzip /app/dataset/logs/2024/01/sensor_a.log
gzip /app/dataset/logs/2024/01/sensor_b.log
gzip /app/dataset/logs/2024/02/sensor_a.log

python3 -c "from gtts import gTTS; tts = gTTS('The primary sensor malfunctioned due to wildlife interference.'); tts.save('/tmp/audio.mp3')"
ffmpeg -y -i /tmp/audio.mp3 /app/field_audio.wav
rm /tmp/audio.mp3

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
