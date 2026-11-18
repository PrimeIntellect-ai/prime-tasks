#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific Python packages
    pip3 install pandas matplotlib scikit-learn pyarrow

    # Create directories
    mkdir -p /home/user/data /home/user/scripts

    # Create initial data file
    cat << 'EOF' > /home/user/data/users.csv
id,name,age,bio
101,Alice,30,hiking outdoors nature
102,Bob,25,gamer coder tech
103,Charlie,31,hiking nature outdoors
104,Diana,26,coder tech gamer
105,Eve,45,cooking baking indoors
EOF

    # Create initial script file
    cat << 'EOF' > /home/user/scripts/validate.py
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv('/home/user/data/users.csv')
plt.hist(df['age'])
plt.show()
plt.savefig('/home/user/data/plot.png')
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
