#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user

python3 -c '
sequence = "A" * 300 + "TTAGGCAT" + "C" * 692
with open("/home/user/genome.txt", "w") as f:
    f.write(sequence)
'

python3 -c '
import random
random.seed(123)
data = [random.gauss(5.0, 1.2) for _ in range(50)]
with open("/home/user/affinity.csv", "w") as f:
    for val in data:
        f.write(f"{val}\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
