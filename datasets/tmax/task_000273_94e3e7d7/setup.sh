#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libsndfile1
    pip3 install --no-cache-dir pytest pandas librosa scikit-learn flask fastapi uvicorn requests soundfile numpy

    mkdir -p /app/audio
    python3 -c "import numpy as np; import soundfile as sf; sr=22050; t=np.linspace(0, 2, int(2*sr), endpoint=False); y=0.5*np.sin(2*np.pi*440*t); sf.write('/app/audio/sample.wav', y, sr)"

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/primary.csv
id,text_description,feature_val
1,this is a test record,10.5
2,another test record with more words,20.1
3,short text,5.5
EOF

    cat << 'EOF' > /home/user/data/secondary.csv
id,category
1,A
2,
3,B
EOF

    cat << 'EOF' > /home/user/etl.py
import pandas as pd
df1 = pd.read_csv('/home/user/data/primary.csv')
df2 = pd.read_csv('/home/user/data/secondary.csv')
df = df1.merge(df2, on='id', how='left')
# Bug: df2 has a missing value for id=2, which causes pandas to cast the whole row's missing parts, but wait, id is used as key.
# Actually, to force id to float, let's make df2 not have id as index, but missing values in the join key if it was right join, or missing values in a column.
# If we want id to silently become float, if df contains NaNs and id is int, older pandas might cast everything. We will just look at the JSON output for pure int.
df.to_csv('/home/user/data/joined.csv', index=False)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
