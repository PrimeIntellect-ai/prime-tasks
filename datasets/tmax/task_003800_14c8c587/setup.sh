#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/inventory.csv
id,product_name,price,weight,length,width,height
1,Lightweight Aluminum Chair,45.0,5.0,2.0,2.0,3.0
2,Heavy Duty Steel Shelving Unit,150.0,80.0,4.0,2.0,6.0
3,Plastic Storage Bin,15.0,2.0,1.5,1.5,1.5
4,Oak Wood Dining Table,,60.0,6.0,3.0,2.5
5,Industrial Warehouse Rack,250.0,,8.0,3.0,10.0
6,Cardboard Box Small,2.0,0.5,1.0,1.0,1.0
7,Lead Block Anomaly,500.0,5000.0,1.0,1.0,1.0
8,Aerogel Sample,1000.0,0.001,2.0,2.0,2.0
9,Broken Item,10.0,5.0,,2.0,2.0
10,Standard Office Desk,120.0,40.0,5.0,2.5,2.5
EOF

    chmod -R 777 /home/user
