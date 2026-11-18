#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data /home/user/results

    cat << 'EOF' > /home/user/data/products.csv
id,product_name,tags
1,Smartphone,electronics mobile phone
2,Laptop,electronics computer work
3,Tablet,electronics mobile computer
4,Invalid,
x,BadId,tag1
5,Desktop,electronics computer gaming
6,Headphones,electronics audio
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
