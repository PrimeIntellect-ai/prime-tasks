#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_group
root:x:0:
admin:x:1001:alice,bob,eve,mallory
users:x:1002:alice,bob,charlie
EOF

    cat << 'EOF' > /home/user/mock_route
Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT                                                       
eth0	00000000	0102A8C0	0003	0	0	100	00000000	0	0	0                                                          
eth0	0002A8C0	00000000	0001	0	0	100	00FFFFFF	0	0	0                                                          
wlan0	0003A8C0	00000000	0001	0	0	600	00FFFFFF	0	0	0                                                          
EOF

    cat << 'EOF' > /home/user/mock_quota
alice:4000:10000
bob:8500:10000
charlie:9000:10000
eve:8000:10000
EOF

    chmod -R 777 /home/user
