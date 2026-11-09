#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/results

    # Create a mock PDB file
    cat << 'EOF' > /home/user/data/protein.pdb
ATOM      1  N   MET A   1      27.340  24.430   2.614  1.00 24.67           N
ATOM      2  CA  MET A   1      26.266  25.413   2.842  1.00 24.32           C
ATOM      3  C   MET A   1      26.913  26.639   3.431  1.00 25.11           C
ATOM      4  O   MET A   1      27.886  26.463   4.130  1.00 25.22           O
ATOM      5  CB  MET A   1      25.112  24.880   3.649  1.00 24.44           C
ATOM      6  CA  LEU A   2      24.111  26.111   4.111  1.00 24.32           C
ATOM      7  CA  VAL A   3      -5.000  -5.000  -5.000  1.00 24.32           C
EOF

    # Create mc_sim.sh
    cat << 'EOF' > /home/user/mc_sim.sh
#!/bin/bash
rm -f /home/user/results/*.score
coords_hash=$(md5sum /home/user/ca_coords.txt | awk '{print $1}')
if [ -z "$coords_hash" ]; then
    echo "Missing ca_coords.txt"
    exit 1
fi
for i in {1..100}; do
    # Generate mock scores spanning different orders of magnitude
    # to make floating point reduction order matter in theory
    awk -v i="$i" 'BEGIN {
        srand(i * 123);
        val = (rand() - 0.2) * (10 ^ (rand() * 5));
        printf "%.15f\n", val;
    }' > "/home/user/results/run_${i}.score"
done
EOF
    chmod +x /home/user/mc_sim.sh

    # Create flawed reduce.sh
    cat << 'EOF' > /home/user/reduce.sh
#!/bin/bash
find /home/user/results -name "*.score" -exec cat {} + | awk '{sum+=$1} END {printf "%.15f\n", sum}'
EOF
    chmod +x /home/user/reduce.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
