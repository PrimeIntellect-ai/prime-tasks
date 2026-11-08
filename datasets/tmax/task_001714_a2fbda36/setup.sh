#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg

    # Install PyTorch CPU version first to save build time and avoid timeout
    pip3 install --no-cache-dir torch torchaudio --index-url https://download.pytorch.org/whl/cpu
    pip3 install --no-cache-dir pytest openai-whisper gTTS

    mkdir -p /app
    mkdir -p /home/user/project_raw

    # Generate the audio file using gTTS
    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
import os
text = "Please prepare the following files for the client delivery: network_config.conf, database_schema.sql, and legacy_handlers.py. Make sure they are converted properly."
tts = gTTS(text=text, lang='en')
tts.save('/app/voice_memo.mp3')
os.system('ffmpeg -y -i /app/voice_memo.mp3 -ar 16000 /app/voice_memo.wav >/dev/null 2>&1')
EOF
    python3 /tmp/gen_audio.py
    rm /app/voice_memo.mp3 /tmp/gen_audio.py

    # Create target files encoded in ISO-8859-1
    echo "network configuration data" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/project_raw/network_config.conf
    echo "CREATE TABLE users (id INT);" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/project_raw/database_schema.sql
    echo "def legacy_handler(): pass" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/project_raw/legacy_handlers.py

    # Create dummy files
    echo "dummy data 1" > /home/user/project_raw/dummy_file_1.txt
    echo "dummy data 2" > /home/user/project_raw/old_notes.md

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
