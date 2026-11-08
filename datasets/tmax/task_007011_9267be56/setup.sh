#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk

    pip3 install pytest pandas scikit-learn matplotlib

    mkdir -p /home/user/data_project
    cd /home/user/data_project

    cat << 'EOF' > raw_data.csv
id,feature1,feature2,feature3,target
1,0.5,1.2,ignore_1,0
2,1.5,0.2,ignore_2,1
3,0.1,0.1,ignore_3,
4,2.5,2.2,ignore_4,1
5,0.3,0.5,ignore_5,0
6,1.1,0.9,ignore_6,1
7,0.8,0.8,ignore_7,0
8,2.0,1.5,ignore_8,
9,1.8,1.2,ignore_9,1
10,0.4,0.3,ignore_10,0
EOF

    cat << 'EOF' > train_model.py
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, RocCurveDisplay
import matplotlib
matplotlib.use('TkAgg') # This needs to be changed to 'Agg'
import matplotlib.pyplot as plt

df = pd.read_csv('processed_data.csv')
X = df[['feature1', 'feature2']]
y = df['target']

model = LogisticRegression()
model.fit(X, y)

auc = roc_auc_score(y, model.predict_proba(X)[:, 1])
with open('metrics.txt', 'w') as f:
    f.write(f"AUC: {auc:.4f}\n")

RocCurveDisplay.from_estimator(model, X, y)
plt.savefig('roc_curve.png')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
