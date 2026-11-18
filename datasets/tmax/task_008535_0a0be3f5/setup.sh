#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data_raw.csv
f1,f2,group,target
0.5,0.1,A,1
0.2,0.9,B,0
0.1,0.2,C,1
0.6,0.2,A,1
0.3,0.8,B,0
0.1,0.1,C,0
0.9,0.5,A,1
0.8,0.4,B,1
0.2,0.3,C,0
0.4,0.5,A,1
EOF

    cat << 'EOF' > /home/user/preprocess.py
import pandas as pd

def main():
    df = pd.read_csv('/home/user/data_raw.csv')

    # Mapping dictionary (missing 'C')
    mapping = {'A': 1, 'B': 2}

    # Bug: Unmapped values become NaN, casting column to float
    df['group_id'] = df['group'].map(mapping)

    df.drop(columns=['group'], inplace=True)
    df.to_csv('/home/user/data_clean.csv', index=False)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/train.py
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score
import json

def main():
    df = pd.read_csv('/home/user/data_clean.csv')

    # Validation check
    if df['group_id'].dtype != 'int64':
        raise TypeError(f"group_id must be strictly int64, got {df['group_id'].dtype}")

    X = df[['f1', 'f2', 'group_id']]
    y = df['target']

    clf = RandomForestClassifier(random_state=42, n_estimators=10)
    score = cross_val_score(clf, X, y, cv=2).mean()

    with open('/home/user/best_score.txt', 'w') as f:
        f.write(str(score))

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
