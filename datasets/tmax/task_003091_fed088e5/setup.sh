#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app

    python3 -c "
import os
import json
import zipfile
import numpy as np
import scipy.io.wavfile as wavfile

# 1. Create dummy audio file
sample_rate = 16000
duration = 10
samples = np.random.randint(-32768, 32767, sample_rate * duration, dtype=np.int16)
wavfile.write('/app/original_transmission.wav', sample_rate, samples)

# 2. Create metadata.json
metadata = {
  'message_start_sec': 2.5,
  'message_end_sec': 7.5,
  'smoothing_window': 5
}
with open('/app/metadata.json', 'w') as f:
    json.dump(metadata, f)

# 3. Create artifacts.zip
with zipfile.ZipFile('/app/artifacts.zip', 'w') as zf:
    zf.write('/app/original_transmission.wav', 'transmission.wav')
    zf.write('/app/metadata.json', 'metadata.json')
    zf.writestr('../evil.txt', 'malicious')
    zf.writestr('../../../../etc/passwd_overwrite', 'malicious')

os.remove('/app/metadata.json')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
