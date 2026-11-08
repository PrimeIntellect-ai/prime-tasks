#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy matplotlib scikit-learn

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd
import scipy.io.wavfile as wavfile

os.makedirs("/app", exist_ok=True)

# 1. Generate Audio and Targets
np.random.seed(42)
sr = 16000
duration = 100  # 100 seconds
y_targets = np.random.uniform(1, 10, duration)

audio = []
for val in y_targets:
    t = np.linspace(0, 1, sr, endpoint=False)
    # Amplitude scales with target, frequency scales with target
    signal = val * np.sin(2 * np.pi * (100 + 50 * val) * t)
    # Add some noise
    signal += np.random.normal(0, 0.5, sr)
    audio.extend(signal)

audio = np.array(audio)
# Normalize to 16-bit PCM
audio_int16 = np.int16(audio / np.max(np.abs(audio)) * 32767)
wavfile.write("/app/sensor_data.wav", sr, audio_int16)

# Save targets
pd.DataFrame({'target': y_targets}).to_csv("/app/targets.csv", index=False)

# 2. Create the broken visualize.py
broken_script = """import matplotlib
matplotlib.use('Template') # BROKEN BACKEND
import matplotlib.pyplot as plt
import scipy.io.wavfile as wavfile
import numpy as np

sr, data = wavfile.read('/app/sensor_data.wav')
chunk = data[:sr] # first second

plt.figure(figsize=(10, 4))
plt.plot(chunk)
plt.title('Waveform of First Second')
plt.savefig('/home/user/waveform.png')
"""
with open("/app/visualize.py", "w") as f:
    f.write(broken_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
