#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/products.txt
  Apple iPhone 14
apple iphone  14
Samsung Galaxy S23
Samsvng Galaxy S23
google pixel 7
Google Pixel  7
Sony Xperia 1
sony xperib 1
  oneplus 11  
EOF

    chmod -R 777 /home/user
