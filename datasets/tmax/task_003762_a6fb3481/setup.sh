#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/proteins.fasta
>PROT_A
MKTVEEDC
>PROT_B
RRYHHCYY
>PROT_C
DDDDEEEE
>PROT_D
KRKRHHH
>PROT_E
MADQLTEEQIAEFKEAFSLFDKDGDGTITTKELGTVMRSL
EOF

    cat << 'EOF' > /home/user/experimental_pi.csv
Protein_ID,Experimental_pI
PROT_A,4.25
PROT_B,8.50
PROT_C,3.10
PROT_D,11.20
PROT_E,4.50
EOF

    chmod -R 777 /home/user
