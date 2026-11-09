#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/archive

    cat << 'EOF' > /home/user/users.csv
user_id,name
1,Alice
2,Bob
3,Charlie
4,David
EOF

    cat << 'EOF' > /home/user/transactions.csv
user_id,item_id
1,101
3,105
4,109
EOF

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd

users = pd.read_csv('/home/user/users.csv')
tx = pd.read_csv('/home/user/transactions.csv')

# Merge data
merged = pd.merge(users, tx, on='user_id', how='left')

# Save output
merged.to_csv('/home/user/output.csv', index=False)
EOF

    cat << 'EOF' > /home/user/archive/run_A.csv
user_id,name,item_id
1,Alice,101.0
2,Bob,
3,Charlie,105.0
EOF

    cat << 'EOF' > /home/user/archive/run_B.csv
user_id,name,item_id
1,Alice,101
3,Charlie,105
4,David,109
EOF

    cat << 'EOF' > /home/user/archive/run_C.csv
user_id,name,item_id
1,Alice,102.0
2,Bob,
3,Charlie,107.0
4,David,109.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
