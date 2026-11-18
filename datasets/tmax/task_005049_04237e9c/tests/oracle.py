#!/usr/bin/env python3
import sys

matrix = {
    'S1': [0.1, 0.4, 0.2, 0.3],
    'S2': [0.5, 0.0, 0.3, 0.2],
    'S3': [0.2, 0.2, 0.4, 0.2],
    'S4': [0.1, 0.3, 0.3, 0.3]
}
states = ['S1', 'S2', 'S3', 'S4']

if len(sys.argv) < 2:
    sys.exit(1)

curr = sys.argv[1]
path = [curr]

for r_str in sys.argv[2:]:
    r = float(r_str)
    probs = matrix[curr]
    cum = 0.0
    next_state = states[-1]
    for i, p in enumerate(probs):
        cum += p
        if r < cum:
            next_state = states[i]
            break
    path.append(next_state)
    curr = next_state

print(" ".join(path))
