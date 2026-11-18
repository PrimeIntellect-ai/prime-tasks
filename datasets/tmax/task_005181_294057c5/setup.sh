#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest emoji gTTS

    mkdir -p /app

    # Generate the voice memo audio file
    cat << 'EOF' > /app/generate_audio.py
from gtts import gTTS
text = "Write a python script that reads from standard input. For each line, count the total number of unicode emojis. Keep track of the previous line's emoji count. If the absolute difference between the current line's emoji count and the previous line's emoji count is strictly greater than two, print the line exactly as it is to standard output. Otherwise, do not print it. Assume the first line's previous count is zero."
tts = gTTS(text)
tts.save("/app/voice_memo.wav")
EOF
    python3 /app/generate_audio.py
    rm /app/generate_audio.py

    # Create the oracle script
    cat << 'EOF' > /app/oracle_log_analyzer.py
import sys
import emoji

def count_emojis(text):
    return emoji.emoji_count(text)

def main():
    prev_count = 0
    for line in sys.stdin:
        current_count = count_emojis(line)
        if abs(current_count - prev_count) > 2:
            sys.stdout.write(line)
        prev_count = current_count

if __name__ == "__main__":
    main()
EOF
    chmod 755 /app/oracle_log_analyzer.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
