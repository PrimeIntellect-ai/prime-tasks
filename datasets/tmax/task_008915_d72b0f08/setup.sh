#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/config_stream.csv
1670000000,srv-01,max_connections,100
1670000005,srv-02,max_connections,200
1670000010,srv-01,timeout,30
1670000015,srv-01,max_connections,100
1670000020,srv-02,max_connections,200
1670000025,srv-01,max_connections,150
1670000030,srv-02,timeout,45
1670000035,srv-01,timeout,30
1670000040,srv-02,max_connections,250
1670000045,srv-03,feature_flag,true
1670000050,srv-03,feature_flag,true
1670000055,srv-03,feature_flag,false
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
