#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/ratings.csv
user_id,item_id,rating,timestamp
u1,i1,4,1610000000
u2,i1,5,1615000000
u3,i2,2,1616000000
u1,i2,3,1617000000
u4,i3,5,1619000000
u2,i1,4,1621000000
u5,i3,1,1622000000
u1,i4,4,1623000000
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
