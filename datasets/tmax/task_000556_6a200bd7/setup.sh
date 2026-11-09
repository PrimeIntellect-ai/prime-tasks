#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/products.csv
id,product_name,category,generated_description
1,Gaming Mouse,Electronics,A high precision wireless gaming mouse with RGB lighting.
2,Yoga Mat,Fitness,Good mat.
3,Stand Mixer,Kitchen,A heavy duty construction vehicle used for mixing cement on large industrial job sites.
4,Desk Lamp,Furniture,Lamp.
5,Null Item,,
6,,Misc,Missing name item.
7,Running Shoes,Apparel,Comfortable lightweight running shoes for daily training.
8,Smartphone Case,Electronics,Protective case for your mobile phone with shock absorption.
9,Wooden Bookshelf,Furniture,This is a very long description that goes on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on about nothing in particular.
10,Water Bottle,Fitness,An elephant is a large mammal found in Africa and Asia.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
