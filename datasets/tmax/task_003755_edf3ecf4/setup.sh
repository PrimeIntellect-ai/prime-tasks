#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest gTTS

mkdir -p /app
python3 -c "
from gtts import gTTS
text = \"Hi, this is the security team. We are seeing a new injection attack in our API. Before deployment, you must block any JSON payload that meets either of these two conditions. First, block it if there is a JSON key named exactly 'execute' at a nesting depth of four or greater. The root object is depth zero. Second, block it if any string value anywhere in the JSON contains the substring 'DROP TABLE', case insensitive. Make sure the proxy and detector catch these.\"
tts = gTTS(text)
tts.save('/app/voicemail.mp3')
"
ffmpeg -i /app/voicemail.mp3 /app/voicemail.wav
rm /app/voicemail.mp3

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
