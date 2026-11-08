#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/products_wide.csv
item_id,attr_color,attr_taste,attr_category
A01,Red and bright,Sweet!,Fruit
A02,Bright red?,Tart,Fruit
B01,Yellow,Sweet!,Fruit
C01,Red!,Umami,Vegetable
C02,Green bright,Umami,Vegetable
EOF

    chmod -R 777 /home/user
