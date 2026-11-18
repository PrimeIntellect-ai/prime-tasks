#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        build-essential \
        wget curl \
        ffmpeg \
        cmake \
        git

    pip3 install pytest gTTS pydub

    mkdir -p /app

    cat << 'EOF' > /app/baseline.csv
time,value
0,20.0
10,21.0
20,23.0
30,27.0
40,29.0
50,30.0
EOF

    python3 -c '
from gtts import gTTS
from pydub import AudioSegment
text = "Operator ID 8831. Second 0, value 20.0. Second 10, value 22.0. Second 30, value 26.0. Second 40, value 150.0. Second 50, value 30.0."
tts = gTTS(text)
tts.save("/tmp/temp.mp3")
sound = AudioSegment.from_mp3("/tmp/temp.mp3")
sound.export("/app/sensor_log.wav", format="wav")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
