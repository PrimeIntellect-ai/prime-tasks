#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx python3-numpy python3-scipy
    pip3 install pytest

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/requirements.txt
Flask==2.0.1
Werkzeug==3.0.0
requests==2.31.0
urllib3<1.26,>=1.21.1
pytest==7.4.0
numpy
scipy
EOF

    mkdir -p /app/audio
    # Create a 16-bit PCM WAV file
    python3 -c "
import numpy as np
from scipy.io import wavfile
sample_rate = 44100
t = np.linspace(0, 1, sample_rate, False)
# Generate a simple 440Hz sine wave, amplitude 10000 (below max 32767)
note = np.sin(440 * t * 2 * np.pi) * 10000
audio = note.astype(np.int16)
wavfile.write('/app/audio/sample.wav', sample_rate, audio)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
