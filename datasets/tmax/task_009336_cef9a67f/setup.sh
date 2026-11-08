#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/generate_data.py
import random

random.seed(42)
states = ['A', 'C', 'G', 'T']
# Underlying Transition probabilities (approx)
# A: [0.4, 0.2, 0.2, 0.2]
# C: [0.1, 0.5, 0.2, 0.2]
# G: [0.25, 0.25, 0.25, 0.25]
# T: [0.2, 0.2, 0.3, 0.3]

transitions = []
for _ in range(5000):
    src = random.choice(states)
    if src == 'A':
        dst = random.choices(states, weights=[4, 2, 2, 2])[0]
    elif src == 'C':
        dst = random.choices(states, weights=[1, 5, 2, 2])[0]
    elif src == 'G':
        dst = random.choices(states, weights=[1, 1, 1, 1])[0]
    else:
        dst = random.choices(states, weights=[2, 2, 3, 3])[0]
    transitions.append(f"{src},{dst}")

with open('/home/user/transitions.csv', 'w') as f:
    f.write('\n'.join(transitions) + '\n')
EOF
python3 /home/user/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
