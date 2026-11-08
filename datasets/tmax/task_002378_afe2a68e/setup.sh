#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /app

    cat << 'EOF' > /app/requirements.txt
numpy==1.21.0
numpy==1.24.0
EOF

    cat << 'EOF' > /app/setup.sh
#!/bin/bash
pip3 install -r /app/requirements.txt
EOF
    chmod +x /app/setup.sh

    cat << 'EOF' > /app/process.py
import wave
import struct

def process_audio(file_path):
    with open(file_path, 'rb') as f:
        data = f.read()

    # simulate infinite loop on corrupted tag
    if b'TAGcorrupted' in data:
        while True:
            pass

    energy = 0
    for i in range(len(data)//2):
        sample = struct.unpack('<h', data[i*2:i*2+2])[0]
        energy += sample**2
    return energy

if __name__ == '__main__':
    print(process_audio('/app/stream.wav'))
EOF

    python3 -c "
import wave
import numpy as np

sample_rate = 44100
duration = 60
samples = np.random.randint(-32768, 32767, sample_rate * duration, dtype=np.int16)

with wave.open('/app/stream.wav', 'wb') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(sample_rate)
    wf.writeframes(samples.tobytes())

with open('/app/stream.wav', 'ab') as f:
    f.write(b'TAGcorrupted_data_that_causes_loops...')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
