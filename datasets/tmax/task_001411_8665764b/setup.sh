#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import os

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/math_raw.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'text'])
    writer.writerow([1, "<p>The solution is <i>x^2 + y^2 = z^2</i>.</p>"])
    writer.writerow([2, "<div>   Solve for x: <b> 2x + 4 = 10 </b> </div>"])
    writer.writerow([3, "<span class='math'> \\int_0^1 x^2 dx = \\frac{1}{3} </span>"])

os.chmod('/home/user/math_raw.csv', 0o644)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
