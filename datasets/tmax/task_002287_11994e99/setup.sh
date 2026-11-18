#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np
import scipy.io.wavfile as wavfile

def generate_reference_sweep(duration=5.0, rate=100):
    t = np.linspace(0, duration, int(duration * rate), endpoint=False)
    # A distinct low-frequency envelope pattern
    envelope = 0.5 * (1 + np.sin(2 * np.pi * 0.5 * t)) * np.exp(-0.2 * t)
    return envelope

reference_envelope = generate_reference_sweep()
os.makedirs("/app", exist_ok=True)
np.savetxt("/app/reference_sweep.csv", reference_envelope, delimiter=",")

def create_recording(filepath, is_evil, rate=16000, duration=5.0):
    t = np.linspace(0, duration, int(duration * rate), endpoint=False)
    # Base clean audio (some random noise + low amplitude sine)
    clean_audio = 0.1 * np.random.randn(len(t)) + 0.2 * np.sin(2 * np.pi * 440 * t)

    gain = np.random.uniform(0.8, 1.2)
    offset = np.random.uniform(-0.05, 0.05)

    if is_evil:
        # We want the windowed absolute average of adjusted_x to equal the reference_envelope.
        # Create a high frequency carrier
        carrier = np.sign(np.sin(2 * np.pi * 3000 * t)) 

        # Upsample envelope to 16kHz
        env_up = np.repeat(reference_envelope, 160)
        # Pad or truncate env_up to match len(t)
        if len(env_up) < len(t):
            env_up = np.pad(env_up, (0, len(t) - len(env_up)))
        else:
            env_up = env_up[:len(t)]

        target_adjusted = env_up * carrier
        # Reverse calibration
        x = (target_adjusted - offset) / gain
        audio = x
    else:
        # Just reverse calibration on clean audio so it's arbitrary
        audio = (clean_audio - offset) / gain

    # Clip and convert to 16-bit PCM
    audio_pcm = np.clip(audio * 32767, -32768, 32767).astype(np.int16)
    wavfile.write(filepath, rate, audio_pcm)

    json_path = filepath.replace(".wav", ".json")
    with open(json_path, "w") as f:
        json.dump({
            "recording_id": os.path.basename(filepath).replace(".wav", ""),
            "gain_factor": float(gain),
            "offset": float(offset)
        }, f)

# Generate sample corpus
os.makedirs("/app/sample_corpus/clean", exist_ok=True)
os.makedirs("/app/sample_corpus/evil", exist_ok=True)
for i in range(3):
    create_recording(f"/app/sample_corpus/clean/sample_clean_{i}.wav", False)
    create_recording(f"/app/sample_corpus/evil/sample_evil_{i}.wav", True)

# Generate hidden corpus
os.makedirs("/app/hidden_corpus/clean", exist_ok=True)
os.makedirs("/app/hidden_corpus/evil", exist_ok=True)
for i in range(10):
    create_recording(f"/app/hidden_corpus/clean/hidden_clean_{i}.wav", False)
    create_recording(f"/app/hidden_corpus/evil/hidden_evil_{i}.wav", True)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
