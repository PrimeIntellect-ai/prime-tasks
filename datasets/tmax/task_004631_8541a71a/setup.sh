#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ratings.csv
user_id,item_id,rating
1,101,5
1,102,3
1,104,2
1,106,1
2,101,4
2,102,3
2,103,1
2,105,5
3,103,4
3,104,5
3,105,4
3,106,5
4,101,5
4,102,4
4,104,1
4,106,2
5,102,2
5,103,5
5,105,5
6,101,4
6,102,
6,104,3
6,105,
EOF

    chmod -R 777 /home/user
