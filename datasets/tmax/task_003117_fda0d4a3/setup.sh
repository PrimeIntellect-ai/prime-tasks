#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np

data = [
    {'transaction_id': 'T001', 'user_id': 'U1', 'ssn': '123456789', 'date': '2023-10-01', 'amount': 100.0},
    {'transaction_id': 'T002', 'user_id': 'U1', 'ssn': '123456789', 'date': '2023-10-02', 'amount': 150.0},
    {'transaction_id': 'T003', 'user_id': 'U1', 'ssn': '123456789', 'date': '2023-10-03', 'amount': 200.0},
    {'transaction_id': 'T004', 'user_id': 'U1', 'ssn': '123456789', 'date': '2023-10-04', 'amount': 250.0},
    {'transaction_id': 'T005', 'user_id': 'U1', 'ssn': '123456789', 'date': '2023-10-05', 'amount': -50.0},
    {'transaction_id': 'T006', 'user_id': 'U1', 'ssn': '123456789', 'date': '2024-01-01', 'amount': 300.0},
    {'transaction_id': 'T007', 'user_id': 'U2', 'ssn': '98765432', 'date': '2023-11-01', 'amount': 50.0},
    {'transaction_id': 'T008', 'user_id': 'U2', 'ssn': '9876543210', 'date': '2023-11-02', 'amount': 50.0},
    {'transaction_id': 'T009', 'user_id': 'U2', 'ssn': '987654321', 'date': '2023-11-03', 'amount': 60.0},
    {'transaction_id': 'T011', 'user_id': 'U3', 'ssn': '111222333', 'date': '2023-12-02', 'amount': 120.0},
    {'transaction_id': 'T010', 'user_id': 'U3', 'ssn': '111222333', 'date': '2023-12-01', 'amount': 100.0},
    {'transaction_id': 'T012', 'user_id': 'U3', 'ssn': '111222333', 'date': '2023-12-02', 'amount': 140.0},
]

df = pd.DataFrame(data)
df.to_csv('/home/user/transactions.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
