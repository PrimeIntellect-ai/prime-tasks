#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg

    # Install CPU-only torch to save download time and space
    pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

    # Install other required packages
    pip3 install --no-cache-dir pytest transformers sentence-transformers faiss-cpu fastapi uvicorn soundfile pydantic gtts

    # Create directories
    mkdir -p /app/data

    # Generate audio file using gTTS and ffmpeg
    python3 -c "
from gtts import gTTS
text = 'Hello, thank you for calling ACME support. My internet connection keeps dropping every five minutes. Have you tried unplugging the power cable and plugging it back in? Yes, I did that but the light is still blinking red. Let me schedule a technician to check the fiber line outside your house.'
tts = gTTS(text)
tts.save('/tmp/temp.mp3')
"
    ffmpeg -i /tmp/temp.mp3 -ar 16000 -ac 1 -c:a pcm_s16le /app/data/support_call.wav
    rm /tmp/temp.mp3

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
