#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc
pip3 install pytest

mkdir -p /home/user

# Generate targets.txt
python3 -c "
import random
random.seed(123)
with open('/home/user/targets.txt', 'w') as f:
    for _ in range(500):
        seq = ''.join(random.choices(['A', 'C', 'G', 'T'], k=50))
        f.write(seq + '\n')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
