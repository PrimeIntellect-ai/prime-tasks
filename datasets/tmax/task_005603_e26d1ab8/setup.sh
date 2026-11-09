#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
text,label
"This is a great product",1
"Terrible experience, awful",0
"I loved it, highly recommend",1
"Worst thing I ever bought",0
"It was okay, not bad",1
"Complete garbage",0
"Amazing quality",1
"Do not buy this",0
"Excellent customer service",1
"Broke on the first day",0
"Very satisfied with my purchase",1
"Waste of money",0
"Good value for the price",1
"Disappointed",0
"Will buy again",1
"Never buying this brand again",0
"Five stars",1
"One star",0
"Fantastic",1
"Horrible",0
EOF

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
import sys

df = pd.read_csv('/home/user/data.csv')

# BUG: Leakage
vec = TfidfVectorizer()
X = vec.fit_transform(df['text'])
y = df['label']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=42)

clf = LogisticRegression(random_state=42)
clf.fit(X_train, y_train)
preds = clf.predict(X_test)
acc = accuracy_score(y_test, preds)
print(acc)
EOF

    chmod +x /home/user/pipeline.py
    chmod -R 777 /home/user
