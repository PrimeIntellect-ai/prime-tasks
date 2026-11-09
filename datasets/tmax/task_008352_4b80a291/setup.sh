#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_kmer_counts.csv
1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0
EOF

    cat << 'EOF' > /home/user/ref_svs.txt
25.00
1.00
0.00
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
