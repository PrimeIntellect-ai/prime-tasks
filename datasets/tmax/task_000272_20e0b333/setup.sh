#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/trace.csv
timestamp,caller,callee,duration
1,main,init,10.5
2,main,process,2.0
3,init,load_config,5.0
4,init,setup_db,4.5
5,process,compute,15.2
6,process,compute,14.8
7,compute,math_op,7.0
8,compute,math_op,7.2
9,process,compute,16.1
10,compute,math_op,8.0
11,compute,math_op,7.5
12,main,process,2.1
13,process,compute,15.5
14,compute,math_op,7.1
15,compute,math_op,7.3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
