#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv ffmpeg curl
    pip3 install pytest gTTS

    mkdir -p /app

    cat << 'EOF' > /app/current_version.txt
1.4.2
EOF

    cat << 'EOF' > /app/data_processor.py
import time
def process_data():
    # Simulate a memory-intensive data processing task
    large_list = [x for x in range(1000000)]
    time.sleep(1)
    return len(large_list)

if __name__ == "__main__":
    process_data()
EOF

    # Generate the audio fixture
    python3 -c "from gtts import gTTS; tts = gTTS('Initiate build for version two point one point zero'); tts.save('/app/build_command.mp3')"
    ffmpeg -i /app/build_command.mp3 /app/build_command.wav
    rm /app/build_command.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
