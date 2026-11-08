#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/org_data.csv
emp_id,mgr_id,name,salary
1,NULL,Alice,200000
2,1,Bob,150000
3,1,Charlie,120000
4,2,Dave,100000
5,2,Eve,110000
6,3,Frank,90000
7,4,Grace,95000
8,5,Heidi,105000
9,5,Ivan,80000
10,3,Judy,115000
EOF

    chmod -R 777 /home/user
