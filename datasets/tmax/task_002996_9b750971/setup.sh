#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        wget \
        gcc \
        make \
        netcat-openbsd \
        gawk

    pip3 install pytest

    mkdir -p /app
    cd /app
    wget https://ftp.gnu.org/gnu/datamash/datamash-1.8.tar.gz
    tar -xzf datamash-1.8.tar.gz
    rm datamash-1.8.tar.gz

    # Introduce the intentional typo
    sed -i 's/bin_PROGRAMS = datamash/bin_PROGRAMS = datamas/g' /app/datamash-1.8/Makefile.in

    # Create user
    useradd -m -s /bin/bash user || true

    # Create transactions.csv
    cat << 'EOF' > /home/user/transactions.csv
tx_id,user_id,amount
1,9223372036854775807,100.50
2,9223372036854775807,50.25
3,1234567890123456789,200.00
4,1234567890123456789,-50.00
5,9999999999999999999,10.00
EOF

    chmod -R 777 /home/user
