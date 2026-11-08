#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest biopython numpy matplotlib

    mkdir -p /home/user
    cat << 'EOF' > /home/user/protein.fasta
>sp|P01308|INS_HUMAN Insulin
MALWMRLLPLLALLALWGPDPAAAFVNQHLCGSHLVEALYLVCGERGFFYTPKTRREAED
LQVGQVELGGGPGAGSLQPLALEGSLQKRGIVEQCCTSICSLYQLENYCN
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
