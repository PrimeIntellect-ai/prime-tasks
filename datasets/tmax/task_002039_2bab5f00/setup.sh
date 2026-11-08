#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequence.fasta
>seq1
ACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDE
EOF

    chmod -R 777 /home/user
