#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/emp.csv
emp_id,name,manager_id,dept_id,salary
E001,Alice,,D1,10000
E002,Bob,E001,D1,8000
E003,Charlie,E001,D2,7000
E004,David,E002,D3,6000
E005,Eve,E003,D2,5000
E006,Frank,,D4,9000
E007,Grace,E004,D5,4000
EOF

    cat << 'EOF' > /home/user/data/proj.csv
emp_id,proj_id
E001,P1
E002,P1
E006,P1
E003,P2
E004,P2
E006,P2
E005,P3
E006,P3
E001,P4
E003,P4
E007,P4
EOF

    chmod -R 777 /home/user
