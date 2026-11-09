#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 make cargo
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/meta.csv
id,city
1,NewYork
2,London
EOF

    cat << 'EOF' > /home/user/data/stream1.csv
ts,id,val
2023-01-01,1,10.0
2023-01-02,1,12.0
2023-01-03,1,14.0
2023-01-04,1,16.0
2023-01-06,2,11.0
EOF

    cat << 'EOF' > /home/user/data/stream2.csv
ts,id,val
2023-01-01,2,5.0
2023-01-02,2,6.0
2023-01-03,2,7.0
2023-01-04,2,8.0
2023-01-05,1,10.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
