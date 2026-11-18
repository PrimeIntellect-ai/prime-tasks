#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo coreutils gawk datamash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data_x.csv
user_id,x_val
101,2.5
102,3.1
103,
104,5.0
105,1.2
106,7.8
107,3.3
108,
109,4.4
110,9.1
EOF

    cat << 'EOF' > /home/user/data_y.csv
user_id,y_val
102,8.0
101,4.5
104,12.1
103,5.0
105,2.1
110,18.5
106,
107,7.2
109,9.0
111,10.0
EOF

    chmod -R 777 /home/user
