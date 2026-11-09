#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/interactions.csv
user_id,item_category,clicks,impressions
1,CatA,5,10
1,CatB,1,5
2,CatA,6,10
2,CatC,1,2
3,CatB,10,20
3,CatC,5,10
4,CatA,0,0
EOF

    chmod -R 777 /home/user
