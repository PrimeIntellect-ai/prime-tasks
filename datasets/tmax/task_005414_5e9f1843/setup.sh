#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest PyJWT gTTS

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
import jwt
import random
import base64
import json
from gtts import gTTS

# Generate Audio
tts = gTTS("The firewall bypass backdoor uses the exact subject claim: delta underscore epsilon underscore nine nine.")
tts.save("/app/intercepted_comms.mp3")

# Generate Clean JWTs
for i in range(50):
    payload = {"sub": f"user{i}"}
    token = jwt.encode(payload, "secret", algorithm="HS256")
    with open(f"/app/corpus/clean/clean_{i}.txt", "w") as f:
        f.write(token)

# Generate Evil JWTs (alg=none)
alg_none_variants = ["none", "None", "NoNe", "NONE"]
for i in range(25):
    header = {"alg": random.choice(alg_none_variants), "typ": "JWT"}
    payload = {"sub": f"user{i}"}

    b64_header = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip('=')
    b64_payload = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')

    token = f"{b64_header}.{b64_payload}."
    with open(f"/app/corpus/evil/evil_alg_{i}.txt", "w") as f:
        f.write(token)

# Generate Evil JWTs (backdoor sub)
for i in range(25):
    payload = {"sub": "delta_epsilon_99"}
    token = jwt.encode(payload, "secret", algorithm="HS256")
    with open(f"/app/corpus/evil/evil_sub_{i}.txt", "w") as f:
        f.write(token)
EOF

    python3 /tmp/setup.py
    ffmpeg -i /app/intercepted_comms.mp3 -acodec pcm_s16le -ar 16000 /app/intercepted_comms.wav
    rm /app/intercepted_comms.mp3
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
