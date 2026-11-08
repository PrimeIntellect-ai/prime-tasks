#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest gTTS
pip3 install torch --index-url https://download.pytorch.org/whl/cpu
pip3 install openai-whisper

mkdir -p /app/www

# Generate the audio file using gTTS for clear transcription
python3 -c "
from gtts import gTTS
tts = gTTS('The backdoor passphrase is black hat magic. Use it to retrieve the hash.')
tts.save('/app/voicemail.mp3')
"
ffmpeg -i /app/voicemail.mp3 /app/voicemail.wav
rm /app/voicemail.mp3

# Create the manifest file
cat << 'EOF' > /app/manifest.sha256
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  /app/www/index.html
a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3  /app/www/login.php
EOF

# Create the web files (index.html matches empty SHA256, login.php is modified)
touch /app/www/index.html
echo "<?php echo 'hacked'; ?>" > /app/www/login.php

# Create the access log
cat << 'EOF' > /app/access.log
192.168.1.42 - - [10/Oct/2023:13:50:00 -0700] "GET /index.html HTTP/1.1" 200 512
192.168.1.50 - - [10/Oct/2023:13:55:36 -0700] "GET /login.php?user=admin' UNION SELECT NULL,NULL,NULL-- HTTP/1.1" 200 1234
192.168.1.51 - - [10/Oct/2023:13:56:00 -0700] "GET /login.php HTTP/1.1" 200 1024
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
