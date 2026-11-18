#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas pyarrow sentence-transformers scipy

    mkdir -p /home/user/data
    mkdir -p /home/user/processed

    cat << 'EOF' > /home/user/data/reviews.csv
review_id,user_id,text
101,1,The screen is decent but it lacks brightness.
102,2,Amazing photos! The battery lasted me two whole days.
103,3,It broke after a week. Terrible build quality.
104,4,Great camera, very good battery life overall.
105,5,Too expensive for what it offers.
106,6,I love the design and the battery is okay.
107,7,Not bad, but the camera could be better in low light.
108,8,Super fast processing, absolutely stunning camera!
109,9,Worst phone I have ever bought. Screen cracked.
110,10,Fantastic battery life, camera is top notch.
EOF

    cat << 'EOF' > /home/user/data/users.csv
user_id,is_verified
1,True
2,True
4,True
6,False
7,True
8,True
10,True
EOF

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd

def process_data():
    reviews = pd.read_csv('/home/user/data/reviews.csv')
    users = pd.read_csv('/home/user/data/users.csv')

    # Bug: This merge converts user_id to float because of NaNs from missing users
    df = pd.merge(reviews, users, on='user_id', how='left')

    # Normally we would save here, but it's broken!
    print(df.dtypes)
    return df

if __name__ == "__main__":
    process_data()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
