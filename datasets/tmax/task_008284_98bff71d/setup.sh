#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/reviews.txt
Me encanta este producto! [PRD-001] es increíble. ⭐⭐⭐⭐⭐
悪い品質。二度と買いません... [PRD-002] ⭐
Decent buy, but expensive. [PRD-001] ⭐⭐⭐
Super fast shipping. [PRD-003] ⭐⭐⭐⭐
No funciona bien. [PRD-002] ⭐⭐
Amazing quality! [PRD-004] ⭐⭐⭐⭐⭐
Passable. [PRD-005] ⭐⭐⭐
EOF

    cat << 'EOF' > /home/user/data/products.csv
ProductID,Category,Price
PRD-001,Electronics,299.99
PRD-002,Home,15.50
PRD-003,Electronics,45.00
PRD-004,Outdoors,120.00
PRD-005,Home,30.00
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
