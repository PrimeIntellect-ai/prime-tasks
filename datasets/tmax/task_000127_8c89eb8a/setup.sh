#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/data
cat << 'EOF' > /home/user/data/generate.py
import random

categories = ['Electronics', 'Clothing', 'Home', 'Toys']
with open('/home/user/data/sales.csv', 'w') as f:
    f.write('tx_id,customer_id,date,category,amount\n')
    for i in range(1, 100001):
        tx_id = f"TX-{i}"
        cust_id = f"CUST-{random.randint(1000, 9999)}"
        date = "2023-10-01"
        cat = random.choice(categories)
        amount = round(random.uniform(10.0, 500.0), 2)
        f.write(f"{tx_id},{cust_id},{date},{cat},{amount}\n")

    # Inject specific known records for testing
    f.write("TX-999991,CUST-55555,2023-10-01,Electronics,100.00\n")
    f.write("TX-999992,CUST-55555,2023-10-01,Electronics,250.50\n")
    f.write("TX-999993,CUST-55555,2023-10-01,Clothing,999.99\n")
    f.write("TX-999994,CUST-10000,2023-10-01,Electronics,50.25\n")
EOF
python3 /home/user/data/generate.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/data
chmod -R 777 /home/user
