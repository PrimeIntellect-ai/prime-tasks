#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.csv
id,val1,val2,val3
1.0,10.0,20.0,5.5
2.0,12.0,21.0,6.1
3.0,11.0,20.5,NaN
4.0,100.0,200.0,50.0
5.0,105.0,195.0,NaN
6.0,102.0,198.0,49.0
7.0,10.5,20.2,5.8
EOF

    chmod -R 777 /home/user
