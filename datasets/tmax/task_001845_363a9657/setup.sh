#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest numpy scipy

mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

# Generate audio file
espeak -w /app/experiment_readout.wav "The baseline mean inference time for the new architecture is precisely 38.4 milliseconds."

# Generate JSON files
cat << 'EOF' > /tmp/generate_data.py
import json
import os
import numpy as np

np.random.seed(42)

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

# Clean corpus
for i in range(50):
    data = np.random.normal(38.4, 2.0, 100).tolist()
    with open(os.path.join(clean_dir, f"clean_{i}.json"), "w") as f:
        json.dump({"inference_times": data}, f)

# Evil corpus - malformed
for i in range(10):
    if i % 2 == 0:
        data = ["NaN", "inf", "not_a_number"]
    else:
        data = []
    with open(os.path.join(evil_dir, f"evil_malformed_{i}.json"), "w") as f:
        json.dump({"inference_times": data}, f)

# Evil corpus - shifted
for i in range(40):
    mean = 39.5 if i % 2 == 0 else 37.3
    data = np.random.normal(mean, 2.0, 100).tolist()
    with open(os.path.join(evil_dir, f"evil_shifted_{i}.json"), "w") as f:
        json.dump({"inference_times": data}, f)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
