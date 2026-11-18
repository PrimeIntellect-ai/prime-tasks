#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy scipy

    mkdir -p /app/data
    mkdir -p /truth

    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
from scipy.io import wavfile

np.random.seed(42)
rate = 16000
duration = 2.0
t = np.linspace(0, duration, int(rate * duration), endpoint=False)

# Clean signals: simulate speech with some low frequency components
clean_val = 0.5 * np.sin(2 * np.pi * 300 * t) + 0.3 * np.sin(2 * np.pi * 500 * t)
clean_test = 0.4 * np.sin(2 * np.pi * 250 * t) + 0.4 * np.sin(2 * np.pi * 600 * t)

# Noise: 440Hz + 2000Hz + white noise
noise = 0.2 * np.sin(2 * np.pi * 440 * t) + 0.2 * np.sin(2 * np.pi * 2000 * t) + 0.05 * np.random.randn(len(t))

noisy_val = clean_val + noise
noisy_test = clean_test + noise

def save_wav(filename, data):
    data = np.clip(data, -1.0, 1.0)
    data_int16 = (data * 32767).astype(np.int16)
    wavfile.write(filename, rate, data_int16)

save_wav("/app/data/val_clean.wav", clean_val)
save_wav("/app/data/val_noisy.wav", noisy_val)
save_wav("/truth/test_clean.wav", clean_test)
save_wav("/app/data/test_noisy.wav", noisy_test)
EOF

    python3 /tmp/generate_audio.py

    cat << 'EOF' > /truth/evaluate.py
import numpy as np
from scipy.io import wavfile

def get_audio_data(filepath):
    rate, data = wavfile.read(filepath)
    if data.dtype == np.int16:
        data = data.astype(np.float32) / 32768.0
    return rate, data

def evaluate():
    try:
        r1, clean = get_audio_data("/truth/test_clean.wav")
        r2, cleaned = get_audio_data("/app/data/test_cleaned.wav")

        if r1 != r2:
            print("Sampling rates do not match.")
            return 1.0

        min_len = min(len(clean), len(cleaned))
        clean = clean[:min_len]
        cleaned = cleaned[:min_len]

        mse = np.mean((clean - cleaned) ** 2)
        print(mse)
        return mse
    except Exception as e:
        print(f"Error: {e}")
        return 1.0

if __name__ == "__main__":
    evaluate()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /truth
    chmod -R 777 /home/user
