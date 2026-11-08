#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk
    pip3 install pytest numpy soundfile

    mkdir -p /app/dataset
    mkdir -p /app/.hidden

    # Create metadata_dirty.csv
    cat << 'EOF' > /app/dataset/metadata_dirty.csv
id,timestamp,text
101,00:01:22,This is a normal sentence.
102,00:01:25,This sentence has a
newline in it.
103,00:01:30,This is a duplicate sentence.
104,00:01:35,This is a duplicate sentence.
105,00:01:40,Another normal sentence.
EOF

    # Create raw_recording.wav
    python3 -c '
import numpy as np
import soundfile as sf

sr = 48000
duration_sec = 5
t = np.linspace(0, duration_sec, sr * duration_sec)
audio = np.sin(2 * np.pi * 440 * t)
audio[sr:3*sr] = 0.0 # 2 seconds silence
audio_stereo = np.column_stack((audio, audio))
sf.write("/app/dataset/raw_recording.wav", audio_stereo, sr)
'

    # Create ref_audio.wav
    ffmpeg -i /app/dataset/raw_recording.wav -ar 16000 -ac 1 -af silenceremove=stop_periods=-1:stop_duration=1:stop_threshold=-50dB /app/.hidden/ref_audio.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
