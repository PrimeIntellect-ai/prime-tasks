#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make sox ffmpeg
    pip3 install pytest pandas numpy

    mkdir -p /app

    # Generate the audio file and CSV logs
    python3 -c "
import wave
import struct
import random

sample_rate = 8000
duration = 100
num_samples = sample_rate * duration

samples = [random.randint(-3276, 3276) for _ in range(num_samples)]

transients = [12.45, 45.12, 89.33]
for t in transients:
    start_idx = int(t * sample_rate)
    for i in range(10):
        if start_idx + i < num_samples:
            samples[start_idx + i] = 29491

with wave.open('/app/sensor_audio.wav', 'w') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(sample_rate)
    data = struct.pack('<' + 'h'*num_samples, *samples)
    wf.writeframes(data)
"

    cat << 'EOF' > /app/machine_logs.csv
Timestamp_sec,Machine_State,Batch_ID
12.0,PROCESSING,B100
45.0,PROCESSING,B101
89.5,PROCESSING,B102
10.0,IDLE,B000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
