#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc file libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/generate_data.py
import csv

data = [
    ["Store_A", "2023-10-05", "120.00", "£"],
    ["Store_B", "2023-10-01", "200.00", "£"],
    ["Store_A", "2023-10-01", "100.00", "£"],
    ["Store_B", "2023-10-03", "250.00", "£"],
    ["Store_A", "2023-10-02", "110.00", "£"],
    ["Store_A", "2023-10-06", "130.00", "£"],
    ["Store_B", "2023-10-02", "210.00", "£"]
]

with open("/home/user/raw_sales.csv", "w", encoding="iso-8859-1", newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["StoreID", "Date", "SalesAmount", "Currency"])
    writer.writerows(data)
EOF

python3 /home/user/generate_data.py
rm /home/user/generate_data.py

chmod -R 777 /home/user
