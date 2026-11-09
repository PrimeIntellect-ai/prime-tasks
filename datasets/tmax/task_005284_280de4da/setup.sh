#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/employees.csv
ID,Name,ManagerID,Role
1,Alice,,CEO
2,Bob,1,VP of Engineering
3,Charlie,1,VP of Sales
4,David,2,Director of Backend
5,Eve,2,Director of Frontend
6,Frank,3,Director of EMEA
7,Grace,4,Engineering Manager
8,Heidi,7,Senior Software Engineer
9,Ivan,7,Software Engineer
10,Judy,6,Account Executive
11,Mallory,,Board Member
12,Trent,11,Advisor
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
