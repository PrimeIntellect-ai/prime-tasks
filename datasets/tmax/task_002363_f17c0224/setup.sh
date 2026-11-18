#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy scipy

    mkdir -p /app

    # Generate the initial state WAV file
    python3 -c "
import numpy as np
from scipy.io import wavfile

init_conditions = np.array([0.1, 0.5, 0.2, 0.8, 0.3, 0.6, 0.4, 0.7, 0.9, 0.2], dtype=np.float32)
data = np.zeros((100, 10), dtype=np.float32)
data[0] = init_conditions
wavfile.write('/app/init_state.wav', 44100, data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
