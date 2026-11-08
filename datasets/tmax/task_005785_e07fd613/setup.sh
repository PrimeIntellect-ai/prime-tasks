#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas scikit-learn

mkdir -p /home/user
cat << 'EOF' > /home/user/products.csv
id,split,description
train_1,train,High performance gaming laptop with fast GPU and RGB lighting
train_2,train,Comfortable cotton t-shirt for everyday wear in summer
train_3,train,Mechanical keyboard with tactile switches for fast typing
train_4,train,Wireless noise-cancelling headphones with long battery life
train_5,train,Ergonomic gaming mouse with high DPI and programmable buttons
test_1,test,Fast mechanical keyboard for gaming and typing with RGB lighting
test_2,test,Blue cotton shirt for casual wear
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
