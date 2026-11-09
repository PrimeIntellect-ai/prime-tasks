#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/generate_data.py
import random

random.seed(42)
ops = ['+', '-', '*']

with open('/home/user/test_data.txt', 'w') as f:
    for _ in range(1000):
        # Generate expressions that evaluate to positive integers
        a = random.randint(10, 50)
        b = random.randint(1, 10)
        c = random.randint(1, 10)
        op1 = random.choice(ops)
        op2 = random.choice(ops)

        expr = f"{a} {op1} {b} {op2} {c}"

        # Ensure it's positive by brute force, fallback to addition if needed
        try:
            val = eval(expr)
            if val <= 0:
                expr = f"{a} + {b} + {c}"
        except:
            expr = f"{a} + {b} + {c}"

        f.write(expr + "\n")
EOF

python3 /home/user/generate_data.py
rm /home/user/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
