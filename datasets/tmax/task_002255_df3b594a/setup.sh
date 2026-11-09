#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest numpy scipy

    mkdir -p /app

    sqlite3 /app/topology.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY);
CREATE TABLE edges (source INTEGER, target INTEGER);
INSERT INTO nodes VALUES (1),(2),(3),(4),(5),(6),(7),(8);
INSERT INTO edges VALUES (1,2), (1,5), (2,3), (5,8), (3,8), (4,8);
CREATE VIEW vw_edges AS SELECT a.source, b.target FROM edges a, edges b;
EOF

    python3 -c "
import numpy as np
from scipy.io.wavfile import write

sample_rate = 8000
duration = 0.5
t = np.linspace(0, duration, int(sample_rate * duration), False)

# DTMF frequencies for '1': 697 Hz and 1209 Hz
# DTMF frequencies for '8': 852 Hz and 1336 Hz
tone1 = np.sin(2 * np.pi * 697 * t) + np.sin(2 * np.pi * 1209 * t)
tone8 = np.sin(2 * np.pi * 852 * t) + np.sin(2 * np.pi * 1336 * t)
silence = np.zeros(int(sample_rate * 0.2))

audio = np.concatenate([tone1, silence, tone8])
# Normalize to 16-bit PCM
audio = np.int16(audio / np.max(np.abs(audio)) * 32767)

write('/app/endpoints.wav', sample_rate, audio)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
