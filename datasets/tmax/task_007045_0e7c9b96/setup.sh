#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    # Create target log files
    echo -n "AAAAABBBCCCDDDDDDDDD" > /home/user/log1.dat
    echo -n "XXYYYZZ" > /home/user/log2.dat
    python3 -c "print('E' * 260 + 'F' * 10, end='')" > /home/user/log3.dat

    # Create the configuration file
    cat << 'EOF' > /home/user/backup.conf
/home/user/log1.dat
/home/user/log2.dat
/home/user/log3.dat
EOF

    chmod 644 /home/user/log1.dat /home/user/log2.dat /home/user/log3.dat /home/user/backup.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
