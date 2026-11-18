#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas biopython

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
MAQAARAATPAAAA
>seq2
MAAAAAAQAAAAAAAPAAAA
>seq3
MAPQAA
>seq4
MAAARAAATAAAAA
>seq5
MARASTAAPA
EOF

    cat << 'EOF' > /home/user/observations.csv
seq_id,time,mutations
seq1,1,10
seq1,2,15
seq2,1,20
seq2,2,16
seq3,1,12
seq4,1,15
seq4,2,15
seq5,1,20
EOF

    chmod -R 777 /home/user
