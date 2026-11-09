#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/proteins.fasta
>Protein_A
MADQLTEEQIAEFKEAFSLFDKDGDGTITTKELGTVMRSL
>Protein_B
MTEYKLVVVGAGGVGKSALTIQLIQNHFVDEYDPTIEDSY
>Protein_C
MVLSEGEWQLVLHVWAKVEADVAGHGQDILIRLFKSHPET
>Protein_D
MSKQYSMVGGTGGIGQALSVIALLKAGYRVIACDINQGAA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
