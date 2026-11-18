#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/proteins.fasta
>Protein_A
MALLHSARVLSGVASAFHPGLAAAASARASSWWAHVEMGPPDPILGVTEAYKRDTNSKK
>Protein_B
MVKVYAPASSANMSVGFDVLGAAVTPVDGALLGDVVTVEAAETFSLNNLGRFADKLPSEP
>Protein_C
MKFLILALCFAAASALSADHIIGGALCASHLIQGPAYKLHTLSLPLSMLLTLG
EOF

    chmod -R 777 /home/user
