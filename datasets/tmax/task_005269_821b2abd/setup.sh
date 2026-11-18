#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import numpy as np

np.random.seed(10)
data1 = np.random.normal(loc=-2.0, scale=1.0, size=1000)
data2 = np.random.normal(loc=3.0, scale=2.0, size=2000)
data = np.concatenate([data1, data2])
np.random.shuffle(data)

np.savetxt('/home/user/sensor_data.csv', data, delimiter=',', fmt='%.6f')
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
