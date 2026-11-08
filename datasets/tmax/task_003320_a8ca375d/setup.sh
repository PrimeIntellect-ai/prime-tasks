#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,f1,f2,f3
1,1.0,2.0,3.0
2,4.0,5.0,6.0
3,7.0,8.0,9.0
EOF

    cat << 'EOF' > /home/user/transform.csv
0.2,0.8,0.1
0.5,0.5,0.5
0.1,0.2,0.9
EOF

    chmod -R 777 /home/user
