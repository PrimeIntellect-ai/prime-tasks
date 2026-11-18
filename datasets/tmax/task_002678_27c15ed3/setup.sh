#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/snp_counts.csv
exposure_time,snp_count
1.0,2
2.0,5
1.5,4
3.0,8
0.5,1
EOF

    cat << 'EOF' > /home/user/reference.txt
2.62
EOF

    chmod -R 777 /home/user
