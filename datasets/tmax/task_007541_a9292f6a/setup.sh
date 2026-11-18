#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv bc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the FASTA file
    cat << 'EOF' > sequences.fasta
>seq1
ATCGATCGAT
>seq2
ATCGATCGATATCGATCGAT
>seq3
ATCGATCGATATCGATCGATATCGATCGAT
EOF

    # Create the buggy optimizer.sh
    cat << 'EOF' > optimizer.sh
#!/bin/bash
# Usage: ./optimizer.sh <sequence_length>
L=$1
P=0.0
step=0.5

# Mock scoring function: Score = -1 * (P - L/10.0)^2 + 50
# Gradient of Score w.r.t P is: -2 * (P - L/10.0)

for i in {1..50}; do
    # Calculate gradient
    grad=$(echo "scale=4; -2 * ($P - $L/10.0)" | bc -l)

    # Update P: P = P + step * grad
    P=$(echo "scale=4; $P + $step * $grad" | bc -l)

    # BUG: Diverging step-size adaptation
    step=$(echo "scale=4; $step * 1.5" | bc -l)
done

echo $P
EOF

    chmod +x optimizer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
