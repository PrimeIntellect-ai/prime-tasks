#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip socat netcat-openbsd jq gawk ffmpeg curl espeak
pip3 install pytest gTTS

mkdir -p /app

# Generate the audio file using gTTS and convert to wav
python3 -c "
from gtts import gTTS
text = 'Dataset recording begins. KinaseA activates ProteaseB. ProteaseB inhibits FactorC. FactorC activates KinaseA. KinaseA phosphorylates ReceptorD. ReceptorD inhibits ProteaseB. End of recording.'
tts = gTTS(text)
tts.save('/app/interactions.mp3')
"
ffmpeg -i /app/interactions.mp3 /app/interactions.wav
rm /app/interactions.mp3

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
