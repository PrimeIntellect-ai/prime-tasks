#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data_a.csv
id,f1,f2,y
1,2.0,3.5,10.0
2,NA,4.0,12.0
3,3.0,1.5,8.0
4,4.0,4.0,15.0
5,5.0,2.0,11.0
6,6.0,5.0,20.0
7,7.0,1.0,9.0
8,8.0,6.0,24.0
9,9.0,3.0,14.0
10,10.0,7.0,28.0
EOF

    cat << 'EOF' > /home/user/data_b.csv
id,f3,f4
1,10.0,100.0
2,12.0,110.0
3,11.0,NA
4,15.0,120.0
5,14.0,130.0
6,18.0,140.0
7,13.0,100.0
8,20.0,150.0
9,16.0,130.0
10,22.0,160.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
