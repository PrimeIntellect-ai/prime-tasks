#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/datasets
    mkdir -p /home/user/clean_data

    # Python script to generate the datasets
    cat << 'EOF' > /tmp/setup_zips.py
import zipfile
import os

os.chdir('/home/user/datasets')

# Safe zip 1
with zipfile.ZipFile('vision_data.zip', 'w') as z:
    z.writestr('images/img1.png', 'fake image data')
    z.writestr('labels.csv', 'img1,cat')

# Safe zip 2 in a subdirectory
os.makedirs('text_data_dir')
with zipfile.ZipFile('text_data_dir/nlp_corpus.zip', 'w') as z:
    z.writestr('train.txt', 'hello world')
    z.writestr('test.txt', 'test data')

# Malicious zip 1 (relative path traversal)
with zipfile.ZipFile('audio_set.zip', 'w') as z:
    z.writestr('audio1.wav', 'fake audio')
    # Malicious entry
    z.writestr('../../../home/user/.bashrc', 'echo "hacked"')

# Malicious zip 2 (absolute path)
with zipfile.ZipFile('text_data_dir/sensor_logs.zip', 'w') as z:
    z.writestr('log1.txt', 'sensor data')
    # Malicious entry
    z.writestr('/etc/shadow', 'root:x:...')
    z.writestr('dir/../../../etc/hosts', '127.0.0.1 malicious.com')
EOF

    python3 /tmp/setup_zips.py
    rm /tmp/setup_zips.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
