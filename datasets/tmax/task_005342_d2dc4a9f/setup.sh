#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gTTS pydub

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/baseline_network.csv
source,target,weight
Alice,Bob,2
Bob,Charlie,3
Alice,Dave,1
Dave,Charlie,2
EOF

    mkdir -p /app
    python3 -c '
from gtts import gTTS
from pydub import AudioSegment
import os

text = "Edge from Charlie to Alice with weight 4. Edge from Dave to Eve with weight 2. Edge from Eve to Charlie with weight 5."
tts = gTTS(text)
tts.save("/app/temp.mp3")
sound = AudioSegment.from_mp3("/app/temp.mp3")
sound.export("/app/recovered_links.wav", format="wav")
os.remove("/app/temp.mp3")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
