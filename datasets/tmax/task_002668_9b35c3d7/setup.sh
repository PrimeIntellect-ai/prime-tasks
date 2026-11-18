#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/incoming_data.csv
id,v1,v2,v3,v4
1,1.0,2.0,3.0,4.0
2,0.0,,0.0,0.0
3,10.0,10.0,10.0,10.0
4,-1.0,,-3.0,
5,,2.5,,1.1
EOF

    cat << 'EOF' > /home/user/.expected_processed_data.csv
id,v1,v2,v3,v4,l2_norm,dot_product,is_outlier
1,1.0000,2.0000,3.0000,4.0000,5.4772,10.5000,0
2,0.0000,0.0000,0.0000,0.0000,0.0000,0.0000,0
3,10.0000,10.0000,10.0000,10.0000,20.0000,30.0000,1
4,-1.0000,0.0000,-3.0000,0.0000,3.1623,-3.5000,0
5,0.0000,2.5000,0.0000,1.1000,2.7313,0.9500,0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
