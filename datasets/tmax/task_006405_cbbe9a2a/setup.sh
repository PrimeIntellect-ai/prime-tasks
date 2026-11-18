#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locales

    cat << 'EOF' > /home/user/locales/en_US.csv
key,text,comment
balance,"Your current balance is $150.00.","User query from john.doe@email.com"
fee,"A transaction fee of $1.50 applies.","Alert system@fintech.net"
promo,"Get $50 off your next purchase of $200.00!","Approved by marketing_lead@promo.co.uk"
EOF

    chmod -R 777 /home/user
