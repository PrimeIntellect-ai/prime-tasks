#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow pytz

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/clean_data

    cat << 'EOF' > /home/user/setup_data.py
import csv
import os

data = {
    'hospital_1.csv': [
        ['patient_name', 'ssn', 'record_date', 'tz', 'HR_00:00', 'HR_06:00', 'HR_12:00', 'HR_18:00'],
        ['Alice Smith', '111-22-3333', '2023-10-15', 'America/New_York', '60', '65', '75', '70'],
        ['Bob Jones', '222-33-4444', '2023-10-15', 'America/New_York', '55', '', '80', '72']
    ],
    'hospital_2.csv': [
        ['patient_name', 'ssn', 'record_date', 'tz', 'HR_00:00', 'HR_06:00', 'HR_12:00', 'HR_18:00'],
        ['Charlie Brown', '333-44-5555', '2023-10-16', 'Europe/London', '62', '68', '77', ''],
        ['Diana Prince', '444-55-6666', '2023-10-16', 'Europe/London', '58', '60', '70', '65']
    ],
    'hospital_3.csv': [
        ['patient_name', 'ssn', 'record_date', 'tz', 'HR_00:00', 'HR_06:00', 'HR_12:00', 'HR_18:00'],
        ['Eve Davis', '555-66-7777', '2023-10-17', 'Asia/Tokyo', '65', '70', '80', '75']
    ],
    'hospital_4.csv': [
        ['patient_name', 'ssn', 'record_date', 'tz', 'HR_00:00', 'HR_06:00', 'HR_12:00', 'HR_18:00'],
        ['Frank White', '666-77-8888', '2023-10-18', 'UTC', '60', '62', '65', '64']
    ]
}

for filename, rows in data.items():
    with open(os.path.join('/home/user/raw_data', filename), 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(rows)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
