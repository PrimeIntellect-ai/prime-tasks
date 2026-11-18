#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo curl
    pip3 install pytest

    mkdir -p /home/user/audit_data
    mkdir -p /home/user/audit_tool

    cat << 'EOF' > /home/user/audit_data/departments.csv
dept_code,dept_name
D1,Retail
D2,Investment
D3,Legal
D4,HR
EOF

    cat << 'EOF' > /home/user/audit_data/users.csv
uid,name,dept_code
1,Alice,D2
2,Bob,D2
3,Charlie,D1
4,Diana,D2
5,Eve,D3
6,Frank,D2
EOF

    cat << 'EOF' > /home/user/audit_data/comms.log
1700000000,1,2
1700000001,3,2
1700000002,4,2
1700000003,5,2
1700000004,6,2
1700000005,2,4
1700000006,1,4
1700000007,5,4
1700000008,2,1
1700000009,4,1
1700000010,5,6
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
