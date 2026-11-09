#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
id,email,category,notes
1,alice@example.com,A,The Equation: 10 + 5. Some other text.
2,bob123@test.com,A,Solve Equation: 20 - 2.
3,charlie@domain.org,A,Equation: 3 * 7.
4,diana@xyz.com,B,Here is Equation: 100 / 4.
5,eve@abc.com,B,Equation: 2 ** 4.
6,frank@hello.net,B,Equation: 50 - 20.
7,grace@mail.com,C,Equation: 5 * 5.
8,heidi@mail.com,C,Equation: 10 + 10.
9,ivan@mail.com,C,Equation: 30 - 6.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
