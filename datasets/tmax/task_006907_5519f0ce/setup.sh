#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/us_sales.csv
Date,Region,Revenue
2023-10-01,US,$1500.50
2023-10-02,US,$999.99
2023-10-03,US,$2000.00
EOF

    cat << 'EOF' > /home/user/data/eu_sales.csv
Date,Region,Revenue
2023-10-01,EU,"1500,50"
2023-10-02,EU,"999,99"
2023-10-03,EU,"2000,00"
EOF

    cat << 'EOF' > /home/user/data/uk_sales.csv
Date,Region,Revenue
2023-10-01,UK,£1200.75
2023-10-02,UK,£800.00
2023-10-03,UK,£3000.25
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
