#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/features.csv
id,feature_value
1,10.5
2,15.2
3,8.1
4,12.3
5,20.0
6,11.0
7,9.5
8,14.8
9,10.0
10,12.0
11,11.0
EOF

    cat << 'EOF' > /home/user/labels.csv
id,label
1,A
2,B
3,A
4,B
5,C
6,A
7,B
8,C
9,A
10,B
11,C
EOF

    cat << 'EOF' > /home/user/split.csv
id,split_name
1,train
2,train
3,train
4,test
5,test
6,train
7,test
8,train
9,train
10,train
11,test
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
