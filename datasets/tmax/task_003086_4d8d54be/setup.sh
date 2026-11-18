#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensors_raw.csv
date,station,temp
2023-10-01,München,10.0
2023-10-02,München,
2023-10-03,München,14.0
2023-10-01,München,10.0
2023-10-01,São Paulo,25.0
2023-10-02,São Paulo,
2023-10-03,São Paulo,29.0
2023-10-04,東京,15.0
2023-10-04,東京,15.0
2023-10-05,東京,18.0
EOF

    chmod -R 777 /home/user
