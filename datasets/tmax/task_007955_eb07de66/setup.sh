#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/reference.csv
sensor_1,5.0,0.5,1.0
sensor_2,2.0,0.5,0.0
sensor_3,10.0,1.2,-2.0
EOF

    python3 -c "
import numpy as np
import os

def generate(name, A, B, C):
    t = np.linspace(0, 10, 50)
    y = A * np.exp(-B * t) + C
    np.savetxt(f'/home/user/data/{name}.txt', np.column_stack((t, y)), delimiter=',', header='t,y', comments='')

generate('sensor_1', 5.0, 0.5, 1.0)
generate('sensor_2', 2.0, 0.1, 0.0)
generate('sensor_3', 10.0, 1.2, -2.0)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
