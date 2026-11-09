#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
item_id,category,price,rating
101,A,10.0,4.0
102,A,-5.0,3.0
103,B,,5.0
104,B,20.0,
105,A,12.0,4.2
106,C,1500.0,1.0
107,C,22.0,
108,B,19.0,4.8
109,A,,3.9
110,C,25.0,2.5
EOF

    chmod -R 777 /home/user
