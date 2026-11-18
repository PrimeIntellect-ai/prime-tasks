#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import json

os.makedirs('/home/user/raw_data', exist_ok=True)

# 1. users.parquet
users_data = {
    'user_id': [101, 102, 103, 104, 105],
    'username': ['alice_x', 'bob_99', 'charlie_c', 'diana_d', 'eve_e'],
    'signup_date': ['2023-01-01', '2023-02-15', '2023-03-10', '2023-04-20', '2023-05-05']
}
df_users = pd.DataFrame(users_data)
df_users.to_parquet('/home/user/raw_data/users.parquet')

# 2. reviews_asia.csv (Shift-JIS)
asia_data = [
    "user_id,review_text\n",
    "102,Terrible!! The packaging was completely destroyed...\n",
    "105,Awe-some! 10/10 would buy again.\n"
]
with open('/home/user/raw_data/reviews_asia.csv', 'w', encoding='shift_jis') as f:
    f.writelines(asia_data)

# 3. reviews_eu.json (UTF-16)
eu_data = [
    {"id": 101, "comment": "Great product.   Really loved it :) "},
    {"id": 103, "comment": "Meh... It's okay, I guess."}
]
with open('/home/user/raw_data/reviews_eu.json', 'w', encoding='utf-16') as f:
    json.dump(eu_data, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
