#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/data_A.csv
user_id,feature_1
1,10.5
2,20.1
3,15.0
4,12.2
EOF

    cat << 'EOF' > /home/user/pipeline/data_B.csv
user_id,feature_2
1,9007199254740993
3,9007199254740995
EOF

    cat << 'EOF' > /home/user/pipeline/labels.csv
user_id,label
1,9007199254741003.5
2,20.1
3,9007199254741010.0
4,12.2
EOF

    cat << 'EOF' > /home/user/pipeline/etl.py
import pandas as pd

df_a = pd.read_csv('data_A.csv')
df_b = pd.read_csv('data_B.csv')

# The bug: left join creates NaNs, feature_2 becomes float64, losing precision
df_merged = pd.merge(df_a, df_b, on='user_id', how='left')
df_merged['feature_2'] = df_merged['feature_2'].fillna(0)

df_merged.to_csv('processed.csv', index=False)
EOF

    cat << 'EOF' > /home/user/pipeline/score.py
import pandas as pd

try:
    df = pd.read_csv('processed.csv')
    labels = pd.read_csv('labels.csv')

    df = pd.merge(df, labels, on='user_id')
    df['prediction'] = df['feature_1'] + df['feature_2']

    mse = ((df['prediction'] - df['label']) ** 2).mean()
    print(f"{mse}")
except Exception as e:
    print(f"Error: {e}")
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
