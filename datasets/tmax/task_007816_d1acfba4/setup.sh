#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    mkdir -p /home/user/data/graphs
    mkdir -p /home/user/data/spectra

    cat << 'EOF' > /home/user/data/graphs/mol_A.edgelist
1 2
1 3
1 4
1 5
2 6
EOF

    cat << 'EOF' > /home/user/data/spectra/mol_A.dat
800 10.5
1500 50.2
1600 80.1
2100 100.0
EOF

    cat << 'EOF' > /home/user/data/graphs/mol_B.edgelist
1 2
1 3
1 4
EOF

    cat << 'EOF' > /home/user/data/spectra/mol_B.dat
1500 90.0
EOF

    cat << 'EOF' > /home/user/data/graphs/mol_C.edgelist
1 2
1 3
1 4
1 5
3 6
3 7
3 8
EOF

    cat << 'EOF' > /home/user/data/spectra/mol_C.dat
900 12.0
1200 45.0
1950 95.5
2200 110.0
EOF

    cat << 'EOF' > /home/user/data/graphs/mol_D.edgelist
1 2
1 3
1 4
1 5
1 6
EOF

    cat << 'EOF' > /home/user/data/spectra/mol_D.dat
1500 90.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
