#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk grep sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import random
import os

os.makedirs("/home/user", exist_ok=True)
random.seed(42)

with open("/home/user/observational_data.csv", "w") as f:
    f.write("ID,Sequence,Binding_Affinity,Concentration\n")
    for i in range(1, 201):
        is_valid = random.choice([True, False])
        if is_valid:
            seq_mid = "".join(random.choices(['A','C','G','T'], k=20))
            seq = "ATGC" + seq_mid + "CGTA"
        else:
            seq = "".join(random.choices(['A','C','G','T'], k=28))

        gc_count = seq.count('G') + seq.count('C')
        gc_content = gc_count / len(seq)

        affinity = 1.5 + 4.2 * gc_content + random.uniform(-0.2, 0.2)
        concentration = random.uniform(5.0, 15.0)

        f.write(f"{i},{seq},{affinity:.4f},{concentration:.4f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
