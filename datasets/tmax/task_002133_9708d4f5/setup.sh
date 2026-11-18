#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip time parallel gawk
pip3 install pytest

# Create directories
mkdir -p /app/txt2csv-tools-1.2
mkdir -p /home/user/raw_data
mkdir -p /home/user/processed
mkdir -p /home/user/by_date

# Create the vendored tool with the perturbation
cat << 'EOF' > /app/txt2csv-tools-1.2/convert.sh
#!/bin/bash
AWK_BIN="owk"
$AWK_BIN 'NR==1 {print $2; next} {print $1 "," $2}' "$1"
EOF
chmod +x /app/txt2csv-tools-1.2/convert.sh

# Generate 5000 test files
python3 -c '
import os
import random
from datetime import datetime, timedelta

base_date = datetime(2023, 1, 1)
os.makedirs("/home/user/raw_data", exist_ok=True)
for i in range(5000):
    date_str = (base_date + timedelta(days=random.randint(0, 30))).strftime("%Y-%m-%d")
    with open(f"/home/user/raw_data/sensor_{i}.dat", "w") as f:
        f.write(f"DATE: {date_str}\n")
        for _ in range(5):
            f.write(f"{random.randint(10,99)} {random.random()}\n")
'

# Create user and set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
