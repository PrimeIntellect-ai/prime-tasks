#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c "
import numpy as np

np.random.seed(123)
ref_data = np.random.normal(loc=50.0, scale=5.0, size=500)
test_data = np.random.normal(loc=48.0, scale=4.5, size=500)

with open('/home/user/ref_latency.txt', 'w') as f:
    for val in ref_data:
        f.write(f'{val}\n')

with open('/home/user/test_latency.txt', 'w') as f:
    for val in test_data:
        f.write(f'{val}\n')
"

    chmod -R 777 /home/user
