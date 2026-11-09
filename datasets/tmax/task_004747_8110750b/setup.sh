#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask

    mkdir -p /app/audio
    mkdir -p /app/audio_math_api/logs
    mkdir -p /app/audio_math_api/client_body
    mkdir -p /app/audio_math_api/proxy_temp
    mkdir -p /app/audio_math_api/fastcgi_temp
    mkdir -p /app/audio_math_api/uwsgi_temp
    mkdir -p /app/audio_math_api/scgi_temp

    # Create dummy wav file
    touch /app/audio/test_sequence.wav

    # Create transcriber.py
    cat << 'EOF' > /app/audio_math_api/transcriber.py
import sys

def transcribe(filepath):
    if "test_sequence.wav" in filepath:
        print("forty two, eight, nineteen")
    else:
        print("one, two, three")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        transcribe(sys.argv[1])
EOF

    # Create app.py with intentional bugs
    cat << 'EOF' > /app/audio_math_api/app.py
from flask import Flask, request, jsonify
import subprocess
import os

app = Flask(__name__)

word_to_num = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40,
    'forty two': 42
}

def parse_spoken_numbers(text):
    words = [w.strip() for w in text.split(',')]
    return [str(word_to_num.get(w, 0)) for w in words]

@app.route('/api/merge')
def merge():
    # Bug 2: expects 'seq' but looks for 'sequence'
    seq = request.args.get('sequence', '')
    file_param = request.args.get('file', '')

    if not seq or not file_param:
        return jsonify({"error": "Missing parameters"}), 400

    wav_path = f"/app/audio/{file_param}.wav"
    if not os.path.exists(wav_path):
        return jsonify({"error": "File not found"}), 404

    try:
        result = subprocess.run(['python3', '/app/audio_math_api/transcriber.py', wav_path], capture_output=True, text=True)
        spoken_text = result.stdout.strip()
        spoken_nums = parse_spoken_numbers(spoken_text)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    seq_nums = [x.strip() for x in seq.split(',')]
    merged_list = seq_nums + spoken_nums

    # Bug 3: sorts alphabetically as strings instead of mathematically
    merged_list = sorted(merged_list)

    return jsonify({"result": merged_list})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    # Create nginx.conf with intentional bugs
    cat << 'EOF' > /app/audio_math_api/nginx.conf
worker_processes 1;
pid /app/audio_math_api/nginx.pid;
error_log /app/audio_math_api/logs/error.log;

events {
    worker_connections 1024;
}

http {
    access_log /app/audio_math_api/logs/access.log;
    client_body_temp_path /app/audio_math_api/client_body;
    proxy_temp_path /app/audio_math_api/proxy_temp;
    fastcgi_temp_path /app/audio_math_api/fastcgi_temp;
    uwsgi_temp_path /app/audio_math_api/uwsgi_temp;
    scgi_temp_path /app/audio_math_api/scgi_temp;

    # Bug 1: malformed limit_req_zone
    limit_req_zone $binary_remote_addr rate=5r/s;

    server {
        listen 8080;

        location /api/ {
            # Bug 1: wrong proxy port
            proxy_pass http://127.0.0.1:9000;
            limit_req zone=mylimit burst=10;
        }
    }
}
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
