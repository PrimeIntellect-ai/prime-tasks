#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy biopython

    useradd -m -s /bin/bash user || true

    python3 -c '
seq = "ATGC" * 375 + "A" * 15
with open("/home/user/gene.fasta", "w") as f:
    f.write(">sequence_1\n" + seq + "\n")
'

    chmod -R 777 /home/user
