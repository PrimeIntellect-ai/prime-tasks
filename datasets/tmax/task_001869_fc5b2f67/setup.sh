#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import tarfile
import os
import hashlib
import io

os.chdir('/home/user')

# Create the secret artifact
artifact_data = b"MOCK_SECRET_DATA_FOR_LAYER_42_" * 1000
expected_hash = hashlib.sha256(artifact_data).hexdigest()

# We will build from the inside out. 
# Layer 42 contains secret_artifact.bin and layer_43.tar (mock end of loop)
current_layer_data = io.BytesIO()
with tarfile.open(fileobj=current_layer_data, mode='w') as tar:
    info = tarfile.TarInfo(name="secret_artifact.bin")
    info.size = len(artifact_data)
    tar.addfile(info, io.BytesIO(artifact_data))

    # Add a dummy layer 43 to simulate the infinite loop continuing
    dummy_data = b"dummy loop data"
    info_dummy = tarfile.TarInfo(name="layer_43.tar")
    info_dummy.size = len(dummy_data)
    tar.addfile(info_dummy, io.BytesIO(dummy_data))

current_layer_bytes = current_layer_data.getvalue()

# Build layers 41 down to 1
for i in range(41, 0, -1):
    next_layer_data = io.BytesIO()
    with tarfile.open(fileobj=next_layer_data, mode='w') as tar:
        info = tarfile.TarInfo(name=f"layer_{i+1}.tar")
        info.size = len(current_layer_bytes)
        tar.addfile(info, io.BytesIO(current_layer_bytes))
    current_layer_bytes = next_layer_data.getvalue()

# Finally, write the root backup
with open('corrupted_backup.tar', 'wb') as f:
    f.write(current_layer_bytes)

# Save the expected hash to a hidden file for verification script access (optional)
with open('/tmp/expected_hash.txt', 'w') as f:
    f.write(expected_hash)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
