#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/config

    cat << 'EOF' > /home/user/data/auth.log
2024-01-01T12:00:00Z ERR Failed login attempt user=admin ip=192.168.1.100
2024-01-01T12:02:00Z OK Successful login user=admin ip=192.168.1.100
2024-01-01T12:05:00Z ERR Failed login attempt user=root ip=10.5.5.1
2024-01-01T12:10:00Z OK Successful login user=user1 ip=10.5.5.1
2024-01-01T12:15:00Z ERR Failed login attempt user=test ip=172.16.0.50
2024-01-01T12:20:00Z ERR Failed login attempt user=service ip=10.99.0.22
EOF

    cat << 'EOF' > /home/user/data/ufw.log
Jan  1 12:01:00 host kernel: [UFW BLOCK] IN=eth0 OUT= MAC=... SRC=192.168.1.100 DST=10.0.0.1 LEN=40 TOS=0x00 PREC=0x00 TTL=245 ID=1001 PROTO=TCP SPT=4444 DPT=8080 WINDOW=1024 RES=0x00 SYN URGP=0
Jan  1 12:06:00 host kernel: [UFW BLOCK] IN=eth0 OUT= MAC=... SRC=10.5.5.1 DST=10.0.0.1 LEN=40 TOS=0x00 PREC=0x00 TTL=245 ID=1002 PROTO=TCP SPT=4444 DPT=22 WINDOW=1024 RES=0x00 SYN URGP=0
Jan  1 12:16:00 host kernel: [UFW BLOCK] IN=eth0 OUT= MAC=... SRC=172.16.0.50 DST=10.0.0.1 LEN=40 TOS=0x00 PREC=0x00 TTL=245 ID=1003 PROTO=TCP SPT=4444 DPT=8080 WINDOW=1024 RES=0x00 SYN URGP=0
Jan  1 12:21:00 host kernel: [UFW ALLOW] IN=eth0 OUT= MAC=... SRC=10.99.0.22 DST=10.0.0.1 LEN=40 TOS=0x00 PREC=0x00 TTL=245 ID=1004 PROTO=TCP SPT=4444 DPT=8080 WINDOW=1024 RES=0x00 SYN URGP=0
EOF

    echo -n "super_secret_compliance_key_2024" > /home/user/config/jwt.secret

    chmod -R 777 /home/user
