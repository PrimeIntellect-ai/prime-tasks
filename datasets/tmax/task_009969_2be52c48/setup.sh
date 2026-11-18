#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy

useradd -m -s /bin/bash user || true

python3 -c "
import numpy as np

np.random.seed(101)
train_data = np.random.normal(0, 1.0, 150)
val_data = np.random.normal(0.2, 1.1, 100)

with open('/home/user/train_feature.txt', 'w') as f:
    for val in train_data:
        f.write(f'{val}\n')

with open('/home/user/val_feature.txt', 'w') as f:
    for val in val_data:
        f.write(f'{val}\n')
"

chmod -R 777 /home/user
