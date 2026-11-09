#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
eu_data = """Time,Value,Location
2023-10-01 12:15:00+02:00,10.0,München
2023-10-01 12:45:00+02:00,20.0,Köln
2023-10-01 13:05:00+02:00,30.0,Berlin
2023-10-01 15:55:00+02:00,12.5,Hamburg"""

na_data = """Timestamp,Measurement,Site
10/01/2023 06:30:00 AM-04:00,15.0,Québec
10/01/2023 07:15:00 AM-04:00,25.0,Montréal
10/01/2023 08:00:00 AM-04:00,35.0,Toronto
10/01/2023 09:30:00 AM-04:00,18.5,Vancouver"""

with open('/home/user/branch_eu.csv', 'w', encoding='iso-8859-1') as f:
    f.write(eu_data)

with open('/home/user/branch_na.csv', 'w', encoding='utf-16') as f:
    f.write(na_data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
