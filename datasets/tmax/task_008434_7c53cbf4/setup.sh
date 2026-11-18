#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Run Python script to generate initial state
    python3 -c "
import numpy as np
import json
import os

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

raw_data = []
valid_rows = []
for i in range(250):
    if i % 7 == 0:
        raw_data.append('CORRUPT,1,2,3')
    elif i % 13 == 0:
        raw_data.append(','.join(map(str, np.random.randn(8))))
    else:
        row = np.random.randn(10)
        raw_data.append(','.join(map(str, row)))
        valid_rows.append(row)

with open('/home/user/data/raw_features.csv', 'w') as f:
    f.write('\n'.join(raw_data) + '\n')

P = np.random.randn(10, 5)
np.savetxt('/home/user/data/projection.csv', P, delimiter=',')

W1 = np.random.randn(5, 8)
b1 = np.random.randn(8)
W2 = np.random.randn(8, 3)
b2 = np.random.randn(3)

weights = {
    'W1': W1.tolist(),
    'b1': b1.tolist(),
    'W2': W2.tolist(),
    'b2': b2.tolist()
}
with open('/home/user/data/weights.json', 'w') as f:
    json.dump(weights, f)

valid_X = np.array(valid_rows)
X_proj = valid_X @ P
norms = np.linalg.norm(X_proj, axis=1, keepdims=True)
X_norm = X_proj / norms

H = X_norm @ W1 + b1
H = np.maximum(H, 0)
Y = H @ W2 + b2
preds = np.argmax(Y, axis=1)

with open('/home/user/expected_predictions.txt', 'w') as f:
    for p in preds:
        f.write(f'{p}\n')
"

    chmod -R 777 /home/user
