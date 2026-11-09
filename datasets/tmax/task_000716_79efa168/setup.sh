#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c '
import numpy as np
np.random.seed(123)
observations = np.random.normal(loc=42.0, scale=3.5, size=1000)
with open("/home/user/observations.csv", "w") as f:
    for val in observations:
        f.write(f"{val}\n")
'

    chmod -R 777 /home/user
