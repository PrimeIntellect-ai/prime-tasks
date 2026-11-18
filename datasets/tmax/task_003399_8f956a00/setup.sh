#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas pyarrow

mkdir -p /home/user
cd /home/user

# Create profiles.csv
cat << 'EOF' > profiles.csv
user_id,feat1,feat2,feat3
100,5,4,6
101,4,3,5
102,1,5,1
103,6,5,7
105,2,1,3
EOF

# Create logs.csv
cat << 'EOF' > logs.csv
user_id,activity_score
100,10
101,8
102,2
103,9
104,5
105,3
EOF

# Create buggy etl.py
cat << 'EOF' > etl.py
import pandas as pd

def run_pipeline():
    profiles = pd.read_csv('/home/user/profiles.csv')
    logs = pd.read_csv('/home/user/logs.csv')

    # Left join introduces NaNs for user 104
    df = pd.merge(logs, profiles, on='user_id', how='left')

    # Save to parquet (silently saves floats due to NaNs)
    df.to_parquet('/home/user/output.parquet', index=False)

    # Calculate similarity on features (ignoring activity_score)
    # NaN propagation ruins correlation for user 104
    features_only = df.set_index('user_id')[['feat1', 'feat2', 'feat3']]
    corr_matrix = features_only.T.corr()

    # Get top 3 similar to user 100
    similar = corr_matrix[100].sort_values(ascending=False).dropna().index[1:4].tolist()

    with open('/home/user/similar_users.txt', 'w') as f:
        f.write(','.join(map(str, similar)))

if __name__ == "__main__":
    run_pipeline()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
