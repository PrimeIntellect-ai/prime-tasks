#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest

mkdir -p /home/user/pipeline

# 1. Create the fake crash dump with the hidden string
head -c 1024 /dev/urandom > /home/user/crash.dmp
echo -n "CONFIG_SCALE_FACTOR=7.5" >> /home/user/crash.dmp
head -c 2048 /dev/urandom >> /home/user/crash.dmp

# 2. Create the conflicting requirements.txt
cat << 'EOF' > /home/user/pipeline/requirements.txt
scipy==1.7.3
numpy==1.24.0
EOF

# 3. Create input.csv
cat << 'EOF' > /home/user/pipeline/input.csv
1.0,2.0,3.0
4.0,5.0,6.0
7.0,8.0,9.0
EOF

# 4. Create expected_output.csv
cat << 'EOF' > /home/user/pipeline/expected_output.csv
7.5,30.0,67.5
120.0,187.5,270.0
367.5,480.0,607.5
EOF

# 5. Create the broken transform.py
cat << 'EOF' > /home/user/pipeline/transform.py
import numpy as np
import pandas as pd # using standard tools

def transform_data(input_file, scale_factor):
    # Read data
    data = np.loadtxt(input_file, delimiter=',')

    # BUG: Incorrect math. It multiplies by scale_factor then squares, 
    # instead of squaring then multiplying by scale factor.
    # It also might be adding instead of multiplying. Let's make it clearly wrong.
    result = (data * scale_factor) + 2 

    return result

if __name__ == "__main__":
    # TODO: Update this scale factor from the crash dump
    SCALE_FACTOR = 1.0 

    output = transform_data('/home/user/pipeline/input.csv', SCALE_FACTOR)
    np.savetxt('/home/user/pipeline/final_output.csv', output, delimiter=',', fmt='%.1f')
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
