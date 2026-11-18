#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app
    mkdir -p /home/user

    # Generate the voicemail.wav
    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
import os

text = "Page received at 3 AM. The iterative solver in the processor script is failing to converge. Please change the denominator in the derivative from cosine of y to sine of y. Also, apply a learning rate of 0.1 to the update step, and increase the maximum iterations to 100. Save the fixed script at /home/user/fixed_processor.py."
tts = gTTS(text=text, lang='en')
tts.save('/app/voicemail.mp3')
os.system('ffmpeg -y -i /app/voicemail.mp3 /app/voicemail.wav >/dev/null 2>&1')
EOF
    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py /app/voicemail.mp3

    # Create processor.py
    cat << 'EOF' > /home/user/processor.py
import sys
import math

def process_value(x, y):
    z = 1.0
    for _ in range(10):
        f = z**2 - x
        df = 2*z + math.cos(y)
        z = z - (f / df)
    return z

if __name__ == "__main__":
    x = float(sys.argv[1])
    y = float(sys.argv[2])
    print(f"{process_value(x, y):.6f}")
EOF

    # Create oracle_processor
    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys
import math

def process_value(x, y):
    z = 1.0
    for _ in range(100):
        f = z**2 - x
        df = 2*z + math.sin(y)
        z = z - 0.1 * (f / df)
    return z

if __name__ == "__main__":
    x = float(sys.argv[1])
    y = float(sys.argv[2])
    print(f"{process_value(x, y):.6f}")
EOF
    chmod +x /app/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
