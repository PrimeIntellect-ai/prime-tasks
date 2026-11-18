#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq multimon-ng sox iputils-ping
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /app/incoming

    # Generate DTMF audio file
    cat << 'EOF' > /tmp/gen_dtmf.py
import wave, math, struct
def generate_tone(f1, f2, duration, sample_rate=8000):
    samples = []
    for i in range(int(duration * sample_rate)):
        t = float(i) / sample_rate
        val = math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)
        samples.append(int(val * 16383))
    return samples

dtmf_freqs = {
    '0': (941, 1336), '3': (697, 1477), '5': (770, 1336),
    '6': (770, 1477), '7': (852, 1209), '8': (852, 1336), '9': (852, 1477)
}

sequence = "8675309"
all_samples = []
for digit in sequence:
    f1, f2 = dtmf_freqs[digit]
    all_samples.extend(generate_tone(f1, f2, 0.2))
    all_samples.extend([0]*int(8000*0.1))

with wave.open('/app/alert.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(8000)
    for s in all_samples:
        w.writeframes(struct.pack('<h', s))
EOF
    python3 /tmp/gen_dtmf.py

    # Create clean corpus
    echo '{"device_id": "sensor-12", "temperature": 45}' > /app/corpus/clean/clean1.json
    echo '{"device_id": "HVAC-alpha-99", "temperature": -10}' > /app/corpus/clean/clean2.json

    # Create evil corpus
    echo '{"device_id": "sensor; rm -rf /", "temperature": 45}' > /app/corpus/evil/evil1.json
    echo '{"device_id": "sensor-1", "temperature": 999}' > /app/corpus/evil/evil2.json
    echo '{"device_id": "sensor_2", "temperature": 45}' > /app/corpus/evil/evil3.json
    echo '{"device_id": "sensor-3"}' > /app/corpus/evil/evil4.json

    # Copy to incoming
    cp /app/corpus/clean/* /app/incoming/
    cp /app/corpus/evil/* /app/incoming/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
