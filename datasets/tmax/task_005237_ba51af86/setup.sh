#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/events.csv
user_id,item_id,clicks,views
1,101,5,10
1,102,1,2
1,104,0,5
2,101,8,12
2,103,2,3
3,102,4,5
3,104,8,10
3,105,1,1
4,101,1,10
4,105,5,5
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
