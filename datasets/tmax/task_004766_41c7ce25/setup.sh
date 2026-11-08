#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py matplotlib

    mkdir -p /home/user
    cat << 'EOF' > /home/user/input.fasta
>seq1
MKVLT
>seq2
ARNDCQEGHILKMFPSTWYV
>seq3
GGG
>seq4
ACGT
>seq5
QWERTY
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
