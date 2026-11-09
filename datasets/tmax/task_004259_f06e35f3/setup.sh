#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest numpy pandas scipy biopython SpeechRecognition pydub

    mkdir -p /app /home/user

    # Generate the audio file using espeak
    espeak -w /app/lab_notes.wav "Update for the kinetics simulation: the fixed step size is causing divergence. Switch to an adaptive solver and set the relative and absolute tolerance to 1e-5."

    # Create a mock PDB file with exactly 42 CA residues
    python3 -c "
with open('/home/user/protein.pdb', 'w') as f:
    for i in range(1, 43):
        f.write(f'ATOM  {i:5d}  CA  ALA A{i:4d}      11.639   6.071  -5.147  1.00  0.00           C  \n')
"

    # Create the diverging simulation script
    cat << 'EOF' > /home/user/sim_kinetics.py
import numpy as np
import pandas as pd

# TODO: Extract Y0 dynamically from /home/user/protein.pdb
Y0 = 100.0 

# ODE: dy/dt = -0.5 * y
def deriv(t, y):
    return -0.5 * y

t_span = (0, 10)
t_eval = np.linspace(t_span[0], t_span[1], 100)

# Diverging Euler implementation
y = np.zeros(len(t_eval))
y[0] = Y0
dt = 2.5 # Too large, will diverge
for i in range(1, len(t_eval)):
    y[i] = y[i-1] + deriv(t_eval[i-1], y[i-1]) * dt

df = pd.DataFrame({'t': t_eval, 'y': y})
df.to_csv('/home/user/trajectory.csv', index=False)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
