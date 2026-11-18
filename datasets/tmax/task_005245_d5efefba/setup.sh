#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate the initial raw backups
    python3 -c "
import os
import random
import string

raw_dir = '/home/user/raw_backups'
os.makedirs(raw_dir, exist_ok=True)

random.seed(42)

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

for i in range(50):
    filename = f'web_node_{random.choice([\"A\", \"B\", \"C\", \"D\"])}_log_{generate_random_string(6)}.dat'
    filepath = os.path.join(raw_dir, filename)

    with open(filepath, 'wb') as f:
        for _ in range(100):
            chunk = os.urandom(10000)
            f.write(chunk)

            num_secrets = random.randint(0, 3)
            for _ in range(num_secrets):
                secret = f'SECRET_TOKEN:{generate_random_string(8)}'.encode('utf-8')
                f.write(secret)
"

    chmod -R 777 /home/user
