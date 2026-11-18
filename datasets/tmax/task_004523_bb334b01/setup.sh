#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential espeak
    pip3 install pytest

    mkdir -p /app/archive

    # Generate the audio file
    espeak -w /app/voicemail.wav "sunflower"

    # Provide a mock whisper tool just in case
    echo '#!/bin/bash' > /usr/local/bin/whisper
    echo 'echo "sunflower"' >> /usr/local/bin/whisper
    chmod +x /usr/local/bin/whisper

    # Generate the XOR encrypted .zdat files
    python3 -c '
import os
key = "sunflower"
def xor_crypt(text):
    return bytes(ord(t) ^ ord(key[i % len(key)]) for i, t in enumerate(text))

files = {
    "fileA.zdat": "alpha_core,v1.0,2021-01-01\n",
    "fileB.zdat": "omega_backup,v2.4,2022-05-12\n",
    "fileC.zdat": "zeta_frontend,v0.9,2023-08-22\n"
}
for fname, content in files.items():
    with open(os.path.join("/app/archive", fname), "wb") as f:
        f.write(xor_crypt(content))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
