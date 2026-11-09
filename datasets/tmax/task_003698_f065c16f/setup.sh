#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    mkdir -p /home/user/inputs
    mkdir -p /home/user/outputs

    cat << 'EOF' > /home/user/inputs/catalog.json
[
  {"id": "P001", "desc": "Ｒｕｎｎｉｎｇ shoes (黒) "},
  {"id": "P001", "desc": "Running shoes (black) - duplicate"},
  {"id": "P002", "desc": "Camiseta de algodón　XL"},
  {"id": "P003", "desc": "Televisor 4K 55\""},
  {"id": "P005", "desc": "   Classic    シャツ  "}
]
EOF

    cat << 'EOF' > /home/user/inputs/inventory.csv
id,price,stock
P001,89.99,120
P002,19.99,50
P003,450.00,10
P004,10.00,0
P005,25.00,200
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
