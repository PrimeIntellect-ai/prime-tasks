#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    # Create directories
    mkdir -p /home/user/voice_math_api
    mkdir -p /app

    # Create a dummy valid wav file for the incident report
    python3 -c '
import wave, struct
with wave.open("/app/incident report 01.wav", "w") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    f.writeframesraw(struct.pack("<h", 0) * 44100)
'

    # Create math_engine.py with the deliberate bug
    cat << 'EOF' > /home/user/voice_math_api/math_engine.py
import math

def calculate_roots(a, b, c):
    # Bug: b**2 + 4*a*c instead of -
    discriminant = b**2 + 4*a*c
    if discriminant < 0:
        return []
    elif discriminant == 0:
        return [-b / (2*a)]
    else:
        root1 = (-b - math.sqrt(discriminant)) / (2*a)
        root2 = (-b + math.sqrt(discriminant)) / (2*a)
        return sorted([root1, root2])
EOF

    # Create preprocess.sh with the missing quotes bug
    cat << 'EOF' > /home/user/voice_math_api/preprocess.sh
#!/bin/bash
# Preprocess audio file
cp $1 /tmp/processed.wav
EOF
    chmod +x /home/user/voice_math_api/preprocess.sh

    # Create app.py
    cat << 'EOF' > /home/user/voice_math_api/app.py
import os
import subprocess
from flask import Flask, request, jsonify
from math_engine import calculate_roots

app = Flask(__name__)

def extract_params(audio_path):
    # Mocking the transcription and extraction for the sake of the environment
    if "incident report 01" in audio_path:
        return 1.0, 0.0, -4.0
    else:
        return 1.0, -3.0, 2.0

@app.route('/calculate', methods=['POST'])
def calculate():
    data = request.json
    if not data or 'audio_path' not in data:
        return jsonify({"error": "Missing audio_path"}), 400

    audio_path = data.get('audio_path')

    # Preprocess
    ret = subprocess.run(['bash', 'preprocess.sh', audio_path])
    if ret.returncode != 0:
        return jsonify({"error": "Preprocessing failed"}), 500

    # Extract
    a, b, c = extract_params(audio_path)

    # Calculate
    roots = calculate_roots(a, b, c)
    return jsonify({"roots": roots})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
