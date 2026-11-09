#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas

mkdir -p /home/user

cat << 'EOF' > /tmp/setup.py
import pandas as pd

data = {
    'region': ['US-East', 'US-West', 'EU-Central', 'US-East', 'EU-Central'],
    'ip_address': ['192.168.1.1', '10.0.0.5', '172.16.0.2', '192.168.1.2', '172.16.0.3'],
    '2023-10-01': [
        '"GET /API/v1/Users?page=1 HTTP/1.1" 200|"POST /Auth/Login HTTP/1.1" 401|"GET /Dash%20board HTTP/1.1" 200',
        '"GET /Images/logo.png HTTP/1.1" 200|"GET /API/v1/Products?id=5 HTTP/1.1" 500',
        '"GET /caf%C3%A9/menu HTTP/1.1" 200',
        'NaN',
        '"POST /API/v1/Checkout HTTP/1.1" 500|"GET /API/v1/Cart HTTP/1.1" 200'
    ],
    '2023-10-02': [
        'NaN',
        '"GET /API/v1/Users?page=2 HTTP/1.1" 200|"GET /Styles/main.css HTTP/1.1" 200',
        '"POST /Auth/Login HTTP/1.1" 401|"GET /API/v1/Users HTTP/1.1" 401',
        '"GET /Home?ref=twitter HTTP/1.1" 200',
        '"GET /API/v1/Products?id=9 HTTP/1.1" 500'
    ],
    '2023-10-03': [
        '"GET /API/v1/Settings HTTP/1.1" 200',
        '"POST /API/v1/Upload%20File HTTP/1.1" 400',
        'NaN',
        '"GET /API/v1/Dashboard HTTP/1.1" 200|"GET /API/v1/Reports HTTP/1.1" 200',
        '"GET /favicon.ico HTTP/1.1" 404'
    ]
}

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_logs.csv', index=False)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
