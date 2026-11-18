#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sales_wide.csv
store_id,store_name,jan_2023,feb_2023,mar_2023
101,Caf\u00e9 Paris,1500,1650,1800
102,El Ni\u00f1o Tacos,2200,2100,2300
103,M\u00fcnchen Bratwurst,1800,1900,1850
EOF

    python3 -c "
with open('/home/user/report.tmpl', 'w') as f:
    f.write('Store: {' + '{.StoreName}' + '} (ID: {' + '{.StoreID}' + '})\nMonth: {' + '{.Month}' + '} -> Sales: {' + '{.Sales}' + '}\n')
"

    chmod -R 777 /home/user
