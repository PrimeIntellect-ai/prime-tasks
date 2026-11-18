#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk sed grep coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
id,name,role
u1,Alice,Engineer
u2,Bob,Manager
u3,Charlie,Engineer
u4,Dave,Manager
u5,Eve,Engineer
u6,Frank,Manager
EOF

    cat << 'EOF' > /home/user/docs.txt
DOC: d1
AUTHOR: u1
CITES: d2, d4
---
DOC: d2
AUTHOR: u2
CITES: 
---
DOC: d3
AUTHOR: u3
CITES: d6, d2
---
DOC: d4
AUTHOR: u4
CITES: d1
---
DOC: d5
AUTHOR: u5
CITES: d6
---
DOC: d6
AUTHOR: u6
CITES: d1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
