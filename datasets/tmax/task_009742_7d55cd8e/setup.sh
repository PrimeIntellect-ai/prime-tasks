#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/products.txt
P001|<p>Apple iPhone 13 Pro (128GB) - Sierra Blue</p>!
P002|Apple   iphone 13 pro 128 gb sierra blue
P003|Samsung Galaxy S22 Ultra 256GB Phantom Black
P004|<b>samsung</b> galaxy s22 ultra 256gb phantom black --- NEW
P005|Sony PlayStation 5 Console - Disc Edition
P006|Sony PlayStation 5 Console (Disc Edition) with extra controller
P007|<div>Sony PlayStation 5 Console Disc Edition</div>
P008|Nintendo Switch OLED Model White Joy-Con
P009|nintendo switch oled model white joy con
EOF

chmod -R 777 /home/user
