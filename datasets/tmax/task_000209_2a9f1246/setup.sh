#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    build-essential \
    cmake \
    git \
    wget \
    ffmpeg \
    espeak

pip3 install pytest

# Setup whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git /opt/whisper
cd /opt/whisper
git checkout v1.5.4
make
bash ./models/download-ggml-model.sh base.en

# Generate audio file
mkdir -p /app/audio
espeak -w /tmp/temp.wav "Alert. Data leakage detected in the pipeline. You must filter out any artifact containing the exact token sequence: protocol zero tango."
ffmpeg -i /tmp/temp.wav -ar 16000 -ac 1 -c:a pcm_s16le /app/audio/leakage_report.wav
rm /tmp/temp.wav

# Create corpora
mkdir -p /app/corpora/clean /app/corpora/evil

cat << 'EOF' > /app/corpora/clean/data1.csv
experiment_id,timestamp,train_features
exp1,1620000000,alpha beta gamma
exp3,1620000010,delta epsilon
EOF

cat << 'EOF' > /app/corpora/evil/data1.csv
experiment_id,timestamp,train_features
exp2,1620000000,alpha protocol zero tango beta
exp4,1620000010,protocol zero tango
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
