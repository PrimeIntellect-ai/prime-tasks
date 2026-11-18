#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
import base64
import hashlib
import json

random.seed(42)

def generate_artifact(size):
    return bytearray(random.getrandbits(8) for _ in range(int(size)))

artifacts = {
    "alpha_build.tar.gz": generate_artifact(1024 * 1024 * 1.2), # ~1.2 MB
    "beta_weights.h5": generate_artifact(1024 * 1024 * 2.5),    # ~2.5 MB
    "gamma_config.bin": generate_artifact(1024 * 300)           # ~300 KB
}

raw_dir = "/home/user/artifacts_raw"
os.makedirs(raw_dir, exist_ok=True)

# Generate single continuous text stream
stream = []
for name, data in artifacts.items():
    stream.append(f"BEGIN_ARTIFACT {name}")
    stream.append("DATA:")
    b64 = base64.b64encode(data).decode('ascii')
    # chunk into lines of 76 chars
    for i in range(0, len(b64), 76):
        stream.append(b64[i:i+76])
    stream.append("END_ARTIFACT")

# Naive split every 150 lines
chunk_size = 150
file_count = 1
for i in range(0, len(stream), chunk_size):
    chunk = stream[i:i+chunk_size]
    with open(os.path.join(raw_dir, f"repo.log.{file_count:03d}"), "w") as f:
        f.write("\n".join(chunk) + "\n")
    file_count += 1

# Pre-calculate truth
truth_manifest = {}
for name, data in artifacts.items():
    truth_manifest[name] = {}
    chunk_idx = 0
    for i in range(0, len(data), 524288):
        chunk_data = data[i:i+524288]
        h = hashlib.sha256(chunk_data).hexdigest()
        truth_manifest[name][f"{name}.part{chunk_idx:03d}"] = h
        chunk_idx += 1

with open("/tmp/truth_manifest.json", "w") as f:
    json.dump(truth_manifest, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
