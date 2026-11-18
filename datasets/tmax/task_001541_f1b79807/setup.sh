#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/audio /app/data

    python3 -c "
import wave, struct, math, csv
sample_rate = 16000
duration = 10
obj = wave.open('/app/audio/signal.wav','w')
obj.setnchannels(1)
obj.setsampwidth(2)
obj.setframerate(sample_rate)

labels = []
rms_expected = []

for window in range(duration):
    # Create varying amplitude per window
    amp = 1000 + window * 500
    samples = []
    sum_sq = 0
    for i in range(sample_rate):
        # 440 Hz sine wave
        val = int(amp * math.sin(2.0 * math.pi * 440.0 * i / sample_rate))
        samples.append(val)
        sum_sq += val * val

    rms = math.sqrt(sum_sq / sample_rate)
    rms_expected.append(rms)

    # Pack to binary
    data = struct.pack('<' + ('h'*len(samples)), *samples)
    obj.writeframesraw(data)

    # Synthetic label: perfectly correlated with a slight offset
    click_rate = 0.5 + (amp / 10000.0)
    labels.append([window, click_rate])

obj.close()

with open('/app/data/labels.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['window_index', 'click_rate'])
    for row in labels:
        writer.writerow(row)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
