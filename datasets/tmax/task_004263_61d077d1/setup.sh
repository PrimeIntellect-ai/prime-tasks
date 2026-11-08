#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > features.csv
user_id,f1,f2,f3
1,10.5,2.0,500
2,12.1,1.8,480
3,9.8,2.5,510
4,15.0,3.0,600
5,11.2,2.1,490
6,20.5,4.5,800
7,10.0,2.2,505
8,19.0,4.2,780
9,14.5,2.9,590
10,11.0,2.0,495
11,100.0,10.0,2000
12,12.5,2.3,520
EOF

    cat << 'EOF' > labels.csv
user_id,label
1,0
2,0
3,0
4,1
5,0
6,2
7,0
8,2
9,1
10,0
12,1
EOF

    cat << 'EOF' > test_ids.txt
4
7
12
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
