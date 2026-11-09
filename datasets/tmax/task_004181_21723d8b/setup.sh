#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest pandas scikit-learn

    mkdir -p /app/data /app/audio

    cat << 'EOF' > /app/data/train.csv
id,feature_A,feature_B,target
1,1.0,2.0,4.5
2,,3.0,9.3
3,100.0,4.0,2.6
4,4.0,,7.0
5,5.0,6.0,16.1
EOF

    cat << 'EOF' > /app/data/test.csv
id,feature_A,feature_B,feature_C
6,2.0,2.0,1.0
7,3.0,4.0,2.0
EOF

    cat << 'EOF' > /app/data/test_hidden.csv
id,target
6,5.0
7,9.0
EOF

    espeak -w /app/audio/dictation.wav "one point five. two point three. negative one point four. zero. five point one."

    cat << 'EOF' > /app/verify.py
import pandas as pd
from sklearn.metrics import mean_absolute_error
import sys

try:
    pred = pd.read_csv('/home/user/predictions.csv').sort_values('id')
    truth = pd.read_csv('/app/data/test_hidden.csv').sort_values('id')

    mae = mean_absolute_error(truth['target'], pred['prediction'])
    print(f"MAE: {mae}")
    if mae <= 2.5:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f"Error evaluating: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
