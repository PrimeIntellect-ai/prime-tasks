#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    mkdir -p /home/user/voicemail_analyzer/logs
    mkdir -p /app

    cat << 'EOF' > /home/user/voicemail_analyzer/wav_parser.py
import struct

def parse_wav(file_bytes):
    # Naive parser
    offset = 0
    riff_magic = file_bytes[offset:offset+4]
    offset += 4
    file_size = struct.unpack_from('<I', file_bytes, offset)[0]
    offset += 4
    wave_magic = file_bytes[offset:offset+4]
    offset += 4

    fmt_magic = file_bytes[offset:offset+4]
    offset += 4
    fmt_size = struct.unpack_from('<I', file_bytes, offset)[0]
    offset += 4

    audio_format, num_channels, sample_rate, byte_rate, block_align, bits_per_sample = struct.unpack_from('<HHIIHH', file_bytes, offset)
    offset += fmt_size

    data_magic = file_bytes[offset:offset+4]
    offset += 4
    data_size = struct.unpack_from('<I', file_bytes, offset)[0]
    offset += 4

    data = file_bytes[offset:offset+data_size]

    return {
        "sample_rate": sample_rate,
        "num_channels": num_channels,
        "bits_per_sample": bits_per_sample,
        "data": data,
        "data_size": data_size
    }
EOF

    cat << 'EOF' > /home/user/voicemail_analyzer/analyzer.py
import sys

def find_silence(data, index):
    if index >= len(data):
        return index
    if data[index] != 0:
        return index
    return find_silence(data, index + 1)

def trim_silence(data):
    # Causes recursion error on long silence
    start_index = find_silence(data, 0)
    return data[start_index:]

def calculate_duration(data_size, sample_rate, num_channels, bits_per_sample):
    bytes_per_sample = bits_per_sample // 8
    frame_size = num_channels * bytes_per_sample
    total_frames = data_size // frame_size

    # Bug: float precision loss
    duration = 0.0
    chunk_duration = 1.0 / sample_rate
    for _ in range(total_frames):
        duration += chunk_duration

    return duration
EOF

    cat << 'EOF' > /home/user/voicemail_analyzer/app.py
from flask import Flask, request, jsonify
from wav_parser import parse_wav
from analyzer import trim_silence, calculate_duration

app = Flask(__name__)

@app.route('/analyze', methods=['POST'])
def analyze():
    # Bug: traceback on missing file
    if 'audio' not in request.files:
        file_data = request.form['audio'] 

    file = request.files['audio']
    file_bytes = file.read()

    parsed = parse_wav(file_bytes)

    # Trim silence (will crash on large files)
    trimmed_data = trim_silence(parsed['data'])

    duration = calculate_duration(
        parsed['data_size'], 
        parsed['sample_rate'], 
        parsed['num_channels'], 
        parsed['bits_per_sample']
    )

    bytes_per_sample = parsed['bits_per_sample'] // 8
    frame_size = parsed['num_channels'] * bytes_per_sample
    samples = parsed['data_size'] // frame_size

    return jsonify({
        "duration": duration,
        "samples": samples,
        "status": "success"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

    python3 -c "
import wave, struct
with wave.open('/app/evidence.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(8000)
    for i in range(1500):
        f.writeframes(struct.pack('<h', 0))
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
