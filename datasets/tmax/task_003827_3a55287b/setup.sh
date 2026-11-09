#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc-dev make ffmpeg
pip3 install pytest SpeechRecognition pydub gTTS

mkdir -p /app
python3 -c "from gtts import gTTS; tts = gTTS('Please configure the server for timezone Europe/Berlin. The alert keyword is SHIBBOLETH.'); tts.save('/app/voicemail.mp3')"
ffmpeg -i /app/voicemail.mp3 /app/voicemail.wav
rm /app/voicemail.mp3

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
