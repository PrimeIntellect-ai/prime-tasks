#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bash
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_flows.log
1670000000 10.0.0.5 192.168.1.50 5368709120 eth0
1670000005 10.0.0.5 192.168.1.50 2147483648 eth0
1670000010 10.0.0.6 172.16.5.10 10737418240 tun0
1670000015 10.0.0.5 10.50.1.99 32212254720 eth1
1670000020 10.0.0.6 172.16.5.10 536870912 tun0
EOF

    cat << 'EOF' > /home/user/pricing.csv
eth0,0.05
eth1,0.08
tun0,0.02
wg0,0.01
EOF

    cat << 'EOF' > /home/user/allowed_routes.txt
192.168.1.50 eth0 wg0
172.16.5.10 tun0 wg0
10.50.1.99 eth1 eth0 tun0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
