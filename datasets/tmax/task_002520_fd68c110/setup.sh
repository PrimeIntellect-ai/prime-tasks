#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy pandas scipy

cat << 'EOF' > /tmp/setup.py
import os
import json
import wave
import struct
import math
import datetime

os.makedirs('/app', exist_ok=True)

# 1. Generate JSONL with intentional unicode errors
jsonl_path = '/app/sensor_logs.jsonl'
with open(jsonl_path, 'w') as f:
    f.write('{"timestamp": "2023-10-01T12:00:00", "value": 10.0}\n')
    f.write('{"timestamp": "2023-10-01T12:10:00", "value": 15.0}\n')
    f.write('{"timestamp": "2023-10-01T12:20:00", "value": 20.0, "note": "bad unicode \\u001"}\n') # broken
    f.write('{"timestamp": "2023-10-01T12:30:00", "value": 25.0}\n')
    f.write('{"timestamp": "2023-10-01T12:40:00", "value": 30.0}\n')
    f.write('{"timestamp": "2023-10-01T12:50:00", "value": 35.0, "note": "broken \\xZZ"}\n') # broken
    f.write('{"timestamp": "2023-10-01T13:00:00", "value": 40.0}\n')

# 2. Generate Morse Code WAV
morse_dict = {
    '0': '-----', '1': '.----', '2': '..---', '5': '.....', '7': '--...',
    '.': '.-.-.-', ' ': ' '
}
text = "1205 12.5 1215 17.5 1225 22.5"

# Audio params
sample_rate = 8000
freq = 1000.0
dot_len = 0.06 # 60ms
dash_len = dot_len * 3
intra_char_space = dot_len
inter_char_space = dot_len * 3
word_space = dot_len * 7

audio_data = []
def append_tone(duration):
    num_samples = int(sample_rate * duration)
    for i in range(num_samples):
        val = int(32767.0 * math.sin(2.0 * math.pi * freq * i / sample_rate))
        audio_data.append(val)

def append_silence(duration):
    num_samples = int(sample_rate * duration)
    audio_data.extend([0] * num_samples)

for word in text.split(' '):
    for char in word:
        code = morse_dict[char]
        for symbol in code:
            if symbol == '.':
                append_tone(dot_len)
            elif symbol == '-':
                append_tone(dash_len)
            append_silence(intra_char_space)
        append_silence(inter_char_space - intra_char_space)
    append_silence(word_space - inter_char_space)

wav_path = '/app/backup_morse.wav'
with wave.open(wav_path, 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)
    for sample in audio_data:
        w.writeframesraw(struct.pack('<h', sample))

# 3. Generate reference.csv
ref_path = '/app/reference.csv'
expected_values = [10.2, 12.4, 15.1, 17.6, 20.0, 22.3, 25.0, 27.8, 30.1, 32.5, 34.9, 37.5, 40.2]
with open(ref_path, 'w') as f:
    f.write('timestamp,value\n')
    dt = datetime.datetime(2023, 10, 1, 12, 0)
    for v in expected_values:
        f.write(f'{dt.strftime("%Y-%m-%d %H:%M:%S")},{v}\n')
        dt += datetime.timedelta(minutes=5)
EOF

python3 /tmp/setup.py
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
