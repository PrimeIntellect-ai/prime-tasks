#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest numpy h5py

    mkdir -p /home/user/ml_data_prep
    cat << 'EOF' > /home/user/ml_data_prep/generate_params.py
import random
random.seed(42)
with open("/home/user/ml_data_prep/params.csv", "w") as f:
    for i in range(200):
        amp = round(random.uniform(1.0, 10.0), 2)
        seed = random.randint(1000, 9999)
        f.write(f"{amp},{seed}\n")
EOF
    python3 /home/user/ml_data_prep/generate_params.py
    rm /home/user/ml_data_prep/generate_params.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
