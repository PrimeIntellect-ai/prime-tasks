#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/collisions.log
1|Mol_A|Mol_B|0.5
2|Mol_A|Mol_C|0.6
3|Mol_B|Mol_C|0.2
4|Mol_D|Mol_A|0.9
5|Mol_E|Mol_F|0.1
6|Mol_G|Mol_A|0.4
7|Mol_C|Mol_G|0.3
8|Mol_B|Mol_E|0.8
9|Mol_H|Mol_A|0.5
10|Mol_A|Mol_I|0.7
11|Mol_J|Mol_B|0.2
12|Mol_K|Mol_C|0.3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
