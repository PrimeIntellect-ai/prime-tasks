#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/bin/run_sim.sh
#!/bin/bash
seq=$1
c_count=$(echo "$seq" | grep -o 'C' | wc -l)
val=10.0
for i in {1..5}; do
    if [ "$c_count" -ge 4 ]; then
        val=$(awk -v v=$val 'BEGIN {print v * 5.5}')
    else
        val=$(awk -v v=$val 'BEGIN {print v * 0.5}')
    fi
    echo "Step $i: $val"
done
EOF
    chmod +x /home/user/bin/run_sim.sh

    cat << 'EOF' > /home/user/data/protein_A.fasta
>sp|P12345|seqA Normal protein
MAGGHII
KLMN
EOF

    cat << 'EOF' > /home/user/data/protein_B.fasta
>sp|P23456|seqB High C content (fails)
MCCCCGII
QQQ
EOF

    cat << 'EOF' > /home/user/data/protein_C.fasta
>sp|P34567|seqC Normal
MLKPPC
EOF

    cat << 'EOF' > /home/user/data/protein_D.fasta
>sp|P45678|seqD High C content (fails)
MCCL
CHCH
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
