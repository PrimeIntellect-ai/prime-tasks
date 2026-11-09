#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /home/user/golden_records.txt
Apple iPhone 14 Pro Max 256GB
Samsung Galaxy S23 Ultra 5G
Google Pixel 7a Unlocked
Sony PlayStation 5 Console Disc Edition
Microsoft Xbox Series X 1TB
Nintendo Switch OLED Model
Dell XPS 15 Laptop Core i7
Apple MacBook Air M2 Chip 8GB
Sony WH-1000XM5 Wireless Headphones
Bose QuietComfort 45 Bluetooth
EOF

    cat << 'EOF' > /home/user/incoming_records.txt
Apple iPhone 13 Mini 128GB
Fresh Organic Bananas 1lb
Sony PS5 Controller DualSense
Wooden Dining Table 6 Seater
Dell Inspiron 15 Laptop
Nike Air Max Running Shoes
Apple MacBook Pro M1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
