#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest flask gunicorn numpy scipy requests

    mkdir -p /home/user/nginx
    mkdir -p /home/user/app
    mkdir -p /app

    cat << 'EOF' > /home/user/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://unix:/home/user/app/wrong_backend.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/main.py
from flask import Flask, request
import numpy as np
import scipy.io.wavfile as wavfile
import io

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process():
    if 'file' not in request.files:
        return "No file", 400

    file = request.files['file']
    file_bytes = file.read()

    sample_rate, data = wavfile.read(io.BytesIO(file_bytes))

    # Intentional bug: dividing by 1000 instead of 32768.0 for int16
    data_float = data.astype(np.float32) / 1000.0

    # Intentional bug: using sum instead of mean
    result = np.sum(np.abs(data_float))

    return str(result)
EOF

    # Generate test audio file
    python3 -c "
import numpy as np
from scipy.io import wavfile
sample_rate = 44100
t = np.linspace(0, 1, sample_rate, endpoint=False)
data = np.sin(2 * np.pi * 440 * t)
data = (data * 32767).astype(np.int16)
wavfile.write('/app/test_audio.wav', sample_rate, data)
"

    useradd -m -s /bin/bash user || true

    chmod -R 777 /var/log/nginx /var/lib/nginx /run || true
    chmod -R 777 /home/user
    chmod -R 777 /app
