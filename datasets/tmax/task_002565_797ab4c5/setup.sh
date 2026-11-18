#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/predictions.csv
id,predicted_value
1,45.5
2,-5.0
3,88.2
4,105.1
5,99.9
6,50.0
EOF

    cat << 'EOF' > /home/user/truth.csv
id,actual_value,category
1,45.0,A
2,10.0,B
3,90.0,A
4,95.0,C
5,100.0,B
6,50.0,C
EOF

    chmod -R 777 /home/user
