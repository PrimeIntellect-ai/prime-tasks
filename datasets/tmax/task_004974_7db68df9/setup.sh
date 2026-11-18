#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/dataset_A.csv
x1,x2,y
1,2,2.0
2,1,5.5
3,4,3.0
4,2,8.0
5,5,5.5
EOF

    cat << 'EOF' > /home/user/datasets/dataset_B.csv
id,label
1,0
2,0
3,0
4,0
5,1
6,1
7,1
8,1
9,1
10,1
EOF

    cat << 'EOF' > /home/user/datasets/dataset_C.csv
f1,f2,target
1,1,2.0
2,0,3.0
0,2,-1.5
EOF

    chown -R user:user /home/user/datasets
    chmod -R 777 /home/user
