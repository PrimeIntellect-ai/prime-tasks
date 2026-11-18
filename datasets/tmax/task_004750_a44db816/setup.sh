#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
user_id,department,name
1,Engineering,Alice
2,Engineering,Bob
3,Sales,Charlie
4,Sales,Diana
5,HR,Eve
6,Engineering,Frank
7,Marketing,Grace
EOF

    cat << 'EOF' > /home/user/interactions.csv
source_id,target_id
1,2
3,2
4,2
2,1
1,3
2,4
5,1
4,1
6,2
7,1
1,7
2,7
7,6
3,7
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
