#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_products.csv
id,description,price
1,red mechanical keyboard cherry mx,100.0
2,red mechanical keyboard cherry mx switch,105.0
3,blue mechanical keyboard cherry mx,95.0
4,wireless optical mouse ergonomic,30.0
5,wireless optical mouse ergonomic usb,
6,gaming monitor 144hz 1080p,200.0
7,gaming monitor 144hz 1080p ips,210.0
8,gaming monitor 144hz,190.0
9,gaming monitor 144hz 1080p ips vesa,
10,usb c hub hdmi ethernet,45.0
11,usb c hub hdmi ethernet sd,48.0
EOF

    mkdir -p /home/user/pipeline
    chmod -R 777 /home/user
