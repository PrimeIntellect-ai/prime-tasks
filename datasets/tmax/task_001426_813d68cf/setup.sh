#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/costs_v1.txt
Auth: 45
Database: 120
Frontend: 85
Logging: 12
Network: 60
Payment: 200
EOF

    python3 -c '
def calc_xor(s):
    res = 0
    for c in s:
        res ^= ord(c)
    return res

lines = [
    ("Auth", "3 * (10 + 5)"),
    ("Database", "2 * (50 + 15)"),
    ("Frontend", "(20 + 5) * 4"),
    ("Logging", "10 + 2"),
    ("Network", "4 * 15")
]

with open("/home/user/formulas_v2.txt", "w") as f:
    for mod, expr in lines:
        f.write(f"{mod}: {expr} | {calc_xor(expr)}\n")
    # Add an invalid one
    f.write("Payment: 5 * 20 | 99\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
