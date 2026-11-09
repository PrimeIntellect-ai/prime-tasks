#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    # Create the audio fixture
    mkdir -p /app
    espeak -w /app/voice_memo.wav "Please update all configuration files. Replace the string 'db_pool_size=10' with 'db_pool_size=50'."

    # Create the legacy configs
    python3 -c "
import os
import random

base_dir = '/home/user/legacy_configs'
os.makedirs(base_dir, exist_ok=True)

random.seed(42)
for i in range(500):
    sub_dir = os.path.join(base_dir, f'group_{i%10}')
    os.makedirs(sub_dir, exist_ok=True)
    file_path = os.path.join(sub_dir, f'config_{i}.ini')

    has_target = random.random() < 0.8
    content = '[database]\n'
    if has_target:
        content += 'db_pool_size=10\nhost=db.internal\n'
    else:
        content += 'db_pool_size=20\nhost=db.internal\n'

    with open(file_path, 'w') as f:
        f.write(content)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
