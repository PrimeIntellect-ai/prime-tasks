#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install numpy pandas matplotlib

    mkdir -p /home/user/workspace/

    # Create model.pth
    cat << 'EOF' > /home/user/workspace/create_model.py
import torch
import torch.nn as nn
model = nn.Sequential(
    nn.Linear(10, 50),
    nn.ReLU(),
    nn.Linear(50, 2)
)
torch.save(model.state_dict(), '/home/user/workspace/model.pth')
EOF
    python3 /home/user/workspace/create_model.py
    rm /home/user/workspace/create_model.py

    # Create data.csv
    cat << 'EOF' > /home/user/workspace/create_data.py
import numpy as np
data = np.random.rand(1000, 10)
np.savetxt('/home/user/workspace/data.csv', data, delimiter=',')
EOF
    python3 /home/user/workspace/create_data.py
    rm /home/user/workspace/create_data.py

    # Create buggy plot.py
    cat << 'EOF' > /home/user/workspace/plot.py
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv('/home/user/workspace/benchmark.csv')
plt.plot(df['batch_size'], df['time_seconds'], marker='o')
plt.title('Inference Benchmark')
plt.xlabel('Batch Size')
plt.ylabel('Time (s)')
plt.show()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
