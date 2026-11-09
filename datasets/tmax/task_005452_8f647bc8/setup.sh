#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app_logs.csv
timestamp,user_id,bytes,duration,status
2023-10-01T10:00,user1,5242880,10.0,200
2023-10-01T10:05,user2,1048576,5.0,200
2023-10-01T10:10,user1,ERR,12.0,500
2023-10-01T10:15,user3,20971520,100.0,200
2023-10-01T10:20,user2,,8.0,400
2023-10-01T10:25,user4,10485760,20.0,200
EOF

    cat << 'EOF' > /home/user/calculate_billing.py
import csv
import json

def process_logs(file_path):
    billing = {}
    with open(file_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            user = row['user_id']
            # Bug 1: Will throw ValueError on 'ERR' or empty string
            b = float(row['bytes'])
            d = float(row['duration'])

            # Bug 2: Formula does not convert bytes to MB
            cost = (b * 0.02) + (d * 0.005)

            if user not in billing:
                billing[user] = 0.0
            billing[user] += cost

    # Round to 4 decimals
    for user in billing:
        billing[user] = round(billing[user], 4)

    with open('/home/user/billing_summary.json', 'w') as f:
        json.dump(billing, f)

if __name__ == '__main__':
    process_logs('/home/user/app_logs.csv')
EOF

    chmod +x /home/user/calculate_billing.py
    chmod -R 777 /home/user
