#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/particles.csv
1,0.0,0.0,0.0,1.5
2,1.0,0.0,0.0,-1.0
3,0.0,2.0,0.0,0.5
4,3.0,3.0,3.0,-0.5
5,0.5,0.5,0.5,1.0
6,-1.0,-1.0,-1.0,-1.5
7,2.0,0.0,0.0,2.0
8,0.0,3.0,0.0,-2.0
EOF

    cat << 'EOF' > /home/user/total_energy.sh
#!/bin/bash
# Simulates a reduction bug by shuffling input, then summing with an unstable accumulator
cat /home/user/edges.csv | shuf | awk -F',' '{
    sum += $3;
    # Simulate low precision float truncation
    sum = int(sum * 100) / 100;
} END {
    printf "Total Energy: %.2f\n", sum
}'
EOF
    chmod +x /home/user/total_energy.sh

    chmod -R 777 /home/user
