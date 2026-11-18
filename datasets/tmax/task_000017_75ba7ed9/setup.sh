#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/experiment_prior.wav "The baseline model has a prior mean of zero point eight two and a variance of zero point zero five."

    # Create the oracle script
    cat << 'EOF' > /app/oracle_tracker
#!/usr/bin/env python3
import sys
import json
import math

PRIOR_MEAN = 0.82
PRIOR_VAR = 0.05
OBS_VAR = 0.01

history = []

def dist(m1, m2):
    return math.sqrt((m1['score'] - m2['score'])**2 + (m1['loss'] - m2['loss'])**2)

for line in sys.stdin:
    if not line.strip(): continue
    data = json.loads(line)

    score = data['score']
    loss = data['loss']
    mid = data['id']

    post_mean = ((PRIOR_MEAN * OBS_VAR) + (score * PRIOR_VAR)) / (PRIOR_VAR + OBS_VAR)
    post_mean_rounded = round(post_mean, 4)

    best_dist = float('inf')
    best_id = "NONE"

    for past in history:
        d = dist(data, past)
        if d < best_dist:
            best_dist = d
            best_id = past['id']

    history.append(data)

    out = {
        "id": mid,
        "posterior_mean": post_mean_rounded,
        "similar_id": best_id
    }
    print(json.dumps(out))
EOF
    chmod +x /app/oracle_tracker

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
