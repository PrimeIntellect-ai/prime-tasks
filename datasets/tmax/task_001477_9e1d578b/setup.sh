#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy h5py

mkdir -p /home/user

cat << 'EOF' > /home/user/setup.py
import os
import h5py
import numpy as np
import random

def setup_env():
    os.makedirs('/home/user', exist_ok=True)

    np.random.seed(42)
    random.seed(42)

    seqs = []
    for _ in range(1000):
        length = random.randint(50, 100)
        if random.random() < 0.3:
            seq = "".join(random.choices(['A', 'C', 'G', 'T'], weights=[0.2, 0.3, 0.3, 0.2], k=length))
            insert_pos = random.randint(0, length - 7)
            seq = seq[:insert_pos] + "GATTACA" + seq[insert_pos+7:]
        else:
            seq = "".join(random.choices(['A', 'C', 'G', 'T'], weights=[0.3, 0.2, 0.2, 0.3], k=length))
            seq = seq.replace("GATTACA", "GATTACT")
        seqs.append(seq.encode('utf-8'))

    with h5py.File('/home/user/sim_data.h5', 'w') as f:
        f.create_dataset('seqs', data=np.array(seqs, dtype='S'))

if __name__ == '__main__':
    setup_env()
EOF

python3 /home/user/setup.py
rm /home/user/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
