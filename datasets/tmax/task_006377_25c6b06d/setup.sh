#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/network_traffic.csv
timestamp,src_ip,dst_ip,bytes,protocol
1620000000,10.0.0.1,10.0.0.2,500,TCP
1620000001,10.0.0.2,10.0.0.3,1500,UDP
1620000002,10.0.0.1,10.0.0.3,200,TCP
1620000003,10.0.0.3,10.0.0.4,800,TCP
1620000004,10.0.0.2,10.0.0.1,300,TCP
1620000005,10.0.0.5,10.0.0.1,100,ICMP
1620000006,10.0.0.4,10.0.0.5,2000,TCP
EOF

    chmod -R 777 /home/user
