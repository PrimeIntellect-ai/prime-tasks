#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils findutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/Mars.txt
Mars|1|9,10,11
Mars|2|19,20,21
Mars|3|29,30,31
EOF

    cat << 'EOF' > /home/user/raw_data/Venus.txt
Venus|1|99,100,101
Venus|2|89,90,91
Venus|3|79,80,81
EOF

    cat << 'EOF' > /home/user/raw_data/Jupiter.txt
Jupiter|1|4,5,6
Jupiter|2|7,8,9
Jupiter|3|10,11,12
EOF

    cat << 'EOF' > /home/user/raw_data/Saturn.txt
Saturn|1|-51,-50,-49
Saturn|2|-41,-40,-39
Saturn|3|-31,-30,-29
EOF

    chown -R user:user /home/user/raw_data
    chmod -R 777 /home/user
