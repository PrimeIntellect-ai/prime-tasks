#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_sim.py
import sys
import numpy as np

seed = int(sys.argv[1])
np.random.seed(seed)
data = np.random.normal(loc=np.arange(50), scale=1.0, size=(1000, 50))
np.save('legacy_out.npy', data)
EOF

    cat << 'EOF' > /home/user/fast_sim.py
import sys
import numpy as np

seed = int(sys.argv[1])
np.random.seed(seed)
data = np.random.normal(loc=np.arange(50), scale=1.0, size=(1000, 50))
# Introduce a slight numerical perturbation on the 25th column
data[:, 24] += 0.0035
np.save('fast_out.npy', data)
EOF

    chmod +x /home/user/legacy_sim.py /home/user/fast_sim.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
