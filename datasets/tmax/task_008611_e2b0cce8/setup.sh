#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

python3 -c "
import os
import random

os.makedirs('/home/user', exist_ok=True)
csv_path = '/home/user/measurements.csv'

random.seed(42)
with open(csv_path, 'w') as f:
    f.write('id,value\n')
    for i in range(10000):
        # Row index 6742 will have the underflow value
        if i == 6742:
            f.write(f'{i},1e-350\n') # Underflows to 0.0 in Python floats
        else:
            # Generate valid small and normal floats
            exponent = random.randint(-100, 100)
            mantissa = random.uniform(1.0, 9.9)
            f.write(f'{i},{mantissa}e{exponent}\n')

# Ensure proper permissions
os.chmod(csv_path, 0o644)
"

chmod -R 777 /home/user
