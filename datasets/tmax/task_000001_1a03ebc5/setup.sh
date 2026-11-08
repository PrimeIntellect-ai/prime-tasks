#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
ids = [f"item_{i}" for i in range(100)]
data = np.random.rand(100, 5)
df = pd.DataFrame(data, columns=["f1", "f2", "f3", "f4", "f5"])
df.insert(0, "id", ids)
df.to_csv("/home/user/data.csv", index=False)
EOF
    python3 /home/user/setup.py

    cat << 'EOF' > /home/user/plot.py
import matplotlib
matplotlib.use('Template') # Produces blank/no output
import matplotlib.pyplot as plt
import pandas as pd
df = pd.read_csv('/home/user/data.csv')
plt.plot(df['f1'], df['f2'])
plt.savefig('/home/user/plot.png')
EOF

    chmod -R 777 /home/user
