#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
id,sequence,target
1,ATGCGTACGTAGCTAG,1.2
2,CGTAGCTAGCTAGCTA,-0.5
3,TTTACGATCGATCGAT,0.8
4,GCGCGCGCGCGCGCGC,-1.5
5,ATATATATATATATAT,2.0
EOF

    chmod -R 777 /home/user
