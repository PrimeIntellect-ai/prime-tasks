#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest flask werkzeug scipy

mkdir -p /home/user/uploads
mkdir -p /app

python3 -c "
import os
import wave
import struct
import math

MORSE_DICT = {
    'S': '...', 'E': '.', 'C': '-.-.', 'U': '..-', 'R': '.-.', 'E': '.',
    '9': '----.', '9': '----.'
}
text = 'SECURE99'
sample_rate = 44100
dot_duration = 0.1
freq = 800.0

def generate_tone(duration, freq, sample_rate):
    num_samples = int(duration * sample_rate)
    return [int(32767 * math.sin(2 * math.pi * freq * i / sample_rate)) for i in range(num_samples)]

def generate_silence(duration, sample_rate):
    return [0] * int(duration * sample_rate)

audio_data = []
for char in text:
    if char in MORSE_DICT:
        code = MORSE_DICT[char]
        for symbol in code:
            if symbol == '.':
                audio_data.extend(generate_tone(dot_duration, freq, sample_rate))
            elif symbol == '-':
                audio_data.extend(generate_tone(dot_duration * 3, freq, sample_rate))
            audio_data.extend(generate_silence(dot_duration, sample_rate))
        audio_data.extend(generate_silence(dot_duration * 2, sample_rate))

with wave.open('/app/intercepted_signal.wav', 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)
    for sample in audio_data:
        wav_file.writeframes(struct.pack('<h', sample))
"

cat << 'EOF' > /home/user/server.py
import os
from flask import Flask, request

app = Flask(__name__)
UPLOAD_DIR = '/home/user/uploads'

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return "No file part", 400

    file = request.files['file']
    filename = request.form.get('filename', file.filename)

    # VULNERABILITY 1: Path traversal
    # VULNERABILITY 2: No authentication
    # VULNERABILITY 3: Insecure permissions
    save_path = os.path.join(UPLOAD_DIR, filename)
    file.save(save_path)

    return "File uploaded successfully", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
