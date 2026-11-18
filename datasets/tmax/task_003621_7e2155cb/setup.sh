#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_users.log
[INFO] User: 101 | email: ALice@Example.com | age: 25 | joined: 2023-05-12
[DEBUG] User: 102 | email: bob@gmail.com | age: 30 | joined: 2022-11-01
[WARN] User: 103 | email: invalid_email.com | age: 22 | joined: 2021-01-01
[INFO] User: 104 | email: dave@Corp.com | age: NaN | joined: 2020-05-05
User: 101 | email: alice@example.com | age: 25 | joined: 2023-05-12
[ERROR] User: 105 | email: EVE@HACKER.NET | age: 45 | joined: 2019-12-31
User: 106 | email: frank@double@at.com | age: 50 | joined: 2018-06-15
User: 107 | email: grace@startup.io | age: -5 | joined: 2024-01-01
[INFO] User: 108 | email: HEIDI@university.edu | age: 19 | joined: 2023-09-01
EOF
    chmod 644 /home/user/raw_users.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
