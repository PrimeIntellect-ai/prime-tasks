#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        fonts-dejavu \
        gcc \
        libc-dev \
        curl

    pip3 install pytest numpy

    mkdir -p /app

    # Generate baseline samples
    python3 -c '
import numpy as np
np.random.seed(42)
n_baseline = 5000
samples = []
for _ in range(n_baseline):
    if np.random.rand() < 0.3:
        samples.append(np.random.normal(-2.0, 0.5))
    else:
        samples.append(np.random.normal(3.0, 1.0))

with open("/app/baseline_samples.txt", "w") as f:
    for val in samples:
        f.write(f"{val}\n")
'

    # Generate distribution spec image
    convert -size 800x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'W1=0.3, MU1=-2.0, SD1=0.5, W2=0.7, MU2=3.0, SD2=1.0'" /app/distribution_spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
