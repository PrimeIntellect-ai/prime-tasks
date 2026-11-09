#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c '
import numpy as np
np.random.seed(123)
data = np.random.exponential(scale=1/2.5, size=1000)
with open("/home/user/data.txt", "w") as f:
    f.write("\n".join(map(str, data)))
'

    chmod -R 777 /home/user
