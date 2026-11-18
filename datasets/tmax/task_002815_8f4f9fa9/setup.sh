#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk findutils
    pip3 install pytest numpy

    # Create the user
    useradd -m -s /bin/bash user || true

    # Run the setup script
    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user/task', exist_ok=True)
os.chdir('/home/user/task')

np.random.seed(42)
true_dist = np.sin(np.linspace(0, np.pi, 1000))
true_dist /= np.sum(true_dist)
np.savetxt('reference.dat', true_dist, fmt='%.8e')

for N in [2, 4, 8, 16]:
    noise_level = 1.0 / N
    for i in range(1, N+1):
        partial = (true_dist / N) + np.random.normal(0, noise_level/N, 1000)
        np.savetxt(f'partial_{N}_{i}.dat', partial.astype(np.float32), fmt='%.8e')

with open('compute_distance.py', 'w') as f:
    f.write('''import sys
import numpy as np
if len(sys.argv) != 3:
    sys.exit(1)
a = np.loadtxt(sys.argv[1])
b = np.loadtxt(sys.argv[2])
print(np.linalg.norm(a - b))
''')

with open('aggregate.sh', 'w') as f:
    f.write('''#!/bin/bash
N=$1
find . -maxdepth 1 -name "partial_${N}_*.dat" | xargs awk '{a[FNR]+=$1} END {for(i=1;i<=1000;i++) print a[i]}' > result_${N}.dat
''')

os.chmod('compute_distance.py', 0o755)
os.chmod('aggregate.sh', 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Set permissions
    chmod -R 777 /home/user
