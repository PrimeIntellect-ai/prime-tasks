#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libsndfile1
    pip3 install --no-cache-dir pytest numpy pandas scipy librosa scikit-learn matplotlib flask fastapi uvicorn requests

    mkdir -p /app
    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import scipy.io.wavfile as wavfile
import os

os.makedirs('/app', exist_ok=True)

# 1. Generate Audio
np.random.seed(42)
sr = 22050
t = np.linspace(0, 1, sr, endpoint=False)
audio_data = []
for i in range(100):
    freq = 100 + i * 5 + np.random.normal(0, 10)
    wave = 0.5 * np.sin(2 * np.pi * freq * t)
    audio_data.append(wave)
full_audio = np.concatenate(audio_data)
wavfile.write('/app/subject_recordings.wav', sr, np.int16(full_audio * 32767))

# 2. Generate CSV
subject_ids = np.arange(100)
ages = np.random.randint(20, 80, size=100).astype(float)
heart_rates = np.random.randint(60, 100, size=100)

# Inject outliers
heart_rates[10] = 160
heart_rates[45] = 180
heart_rates[99] = 210

# Inject missing values
ages[5] = np.nan
ages[50] = np.nan
ages[88] = np.nan

# Labels
diagnoses = np.random.randint(0, 2, size=100)

df = pd.DataFrame({
    'subject_id': subject_ids,
    'age': ages,
    'heart_rate': heart_rates,
    'diagnosis': diagnoses
})
df.to_csv('/app/subject_metadata.csv', index=False)

# 3. Create broken plot script
with open('/app/plot_clusters.py', 'w') as f:
    f.write('''import matplotlib
# Misconfigured backend for headless
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
import pandas as pd

# The agent should load their dataset and plot here
# plt.scatter(df['pca_1'], df['pca_2'])
# plt.savefig('/home/user/pca_clusters.png')
''')
EOF
    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
