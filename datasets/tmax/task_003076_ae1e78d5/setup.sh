#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/raw_data
    mkdir -p /home/user/processed

    # Create batch_A.csv
    cat << 'EOF' > /home/user/raw_data/batch_A.csv
id,category,price,quantity
A1B2C3D4,Electronics,299.99,2
X9Y8Z7W6,Clothing,45.50,1
F1F2F3F4,Food,12.00,5
H8G7F6E5,Electronics,10.00,10
EOF

    # Create batch_B.csv
    cat << 'EOF' > /home/user/raw_data/batch_B.csv
id,category,price,quantity
V1V2V3V4,Electronics,-10.0,1
B1B2B3B4,Toys,15.0,2
C1C2C3C4,Clothing,20.0,0
D1D2D3D4,Food,5.0,10
E1E2E3E4,Food,abc,1
F1234567,Electronics,100.0,2
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
