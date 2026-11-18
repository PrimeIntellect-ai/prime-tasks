#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network_traffic.csv
timestamp,src_ip,dst_ip,bytes
1620000000,10.0.0.1,10.0.0.2,500
1620000005,10.0.0.2,10.0.0.1,300
1620000010,10.0.0.1,10.0.0.3,1200
1620000015,10.0.0.3,10.0.0.4,150
1620000020,10.0.0.4,10.0.0.1,200
1620000025,10.0.0.5,10.0.0.6,8000
1620000030,10.0.0.6,10.0.0.5,1000
1620000035,192.168.1.1,192.168.1.2,4000
1620000040,192.168.1.2,192.168.1.3,5000
1620000045,192.168.1.3,192.168.1.1,3000
1620000050,192.168.1.4,192.168.1.5,50
1620000055,10.0.0.5,10.0.0.7,500
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
