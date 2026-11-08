#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/pop_A.fasta
>seqA1
GGGGATGCGTACGGGGGGGGGGGGGGGGGG
>seqA2
TTTTATGCGTACCTTTTTTTTTTTTTTTTT
>seqA3
AAAAATGCATACGAAAAAAAAAAAAAAAAA
>seqA4
CCCCATGCGTACGCCCCCCCCCCCCCCCCC
>seqA5
GGGGATGCGTACGGGGGATGCGTACGGGGG
EOF

    cat << 'EOF' > /home/user/pop_B.fasta
>seqB1
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
>seqB2
TTTTTTTTTTTTTTTTTTTTTTTTTTTTTT
>seqB3
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
>seqB4
GGCGCGCGCGCGCGCGCGCGCGCGCGCGCG
>seqB5
CGCGCGCGCGCGCGCGCGCGCGCGCGCGCG
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
