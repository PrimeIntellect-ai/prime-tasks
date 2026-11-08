#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest gTTS pydub

# Create the required directory
mkdir -p /app/data

# Generate the audio file with the hidden ground truth transcript
python3 -c "
from gtts import gTTS
from pydub import AudioSegment

text = 'Sensor Alpha twenty two point five. Sensor Beta twenty one point zero. Sensor Alpha twenty three point one. Sensor Beta twenty point eight. Sensor Alpha twenty two point eight. Sensor Beta twenty one point two.'
tts = gTTS(text=text, lang='en')
tts.save('/tmp/temp.mp3')

# Convert to WAV format as requested
audio = AudioSegment.from_mp3('/tmp/temp.mp3')
audio.export('/app/data/telemetry_audio.wav', format='wav')
"

# Clean up temp file
rm /tmp/temp.mp3

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
