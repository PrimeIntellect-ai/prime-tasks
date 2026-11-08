#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make curl
    pip3 install pytest

    mkdir -p /app/text_prep_serve/data
    mkdir -p /app/text_prep_serve/src
    mkdir -p /app/text_prep_serve/models

    cat << 'EOF' > /app/text_prep_serve/requirements.txt
pandas
scikit-learn
fastapi
uvicorn
EOF

    cat << 'EOF' > /app/text_prep_serve/Makefile
install:
	pip install -r requirments.txt
EOF

    cat << 'EOF' > /app/text_prep_serve/data/texts.csv
id,text
1,apple orange banana
2,apple orange
3,banana orange
4,apple banana
5,apple orange
6,banana orange
7,apple banana
8,apple orange
9,rareword testword
10,rareword testword
EOF

    cat << 'EOF' > /app/text_prep_serve/data/labels.csv
id,label
1,0
2,0
3,1
4,1
5,0
6,1
7,1
8,0
9,1
10,1
EOF

    cat << 'EOF' > /app/text_prep_serve/src/prepare.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
import joblib
import os
import numpy as np

def main():
    texts = pd.read_csv('../data/texts.csv')
    labels = pd.read_csv('../data/labels.csv')
    df = pd.merge(texts, labels, on='id')

    vectorizer = TfidfVectorizer()
    X = vectorizer.fit_transform(df['text'])
    y = df['label'].values
    split_idx = int(len(df) * 0.8)
    X_train, X_test = X[:split_idx], X[split_idx:]
    y_train, y_test = y[:split_idx], y[split_idx:]

    os.makedirs('../models', exist_ok=True)
    joblib.dump(vectorizer, '../models/vectorizer.pkl')

    np.random.seed(42)
    n_models = 3
    for i in range(n_models):
        idx = np.random.choice(len(X_train.toarray()), len(X_train.toarray()), replace=True)
        X_b = X_train[idx]
        y_b = y_train[idx]
        clf = LogisticRegression()
        clf.fit(X_b, y_b)
        joblib.dump(clf, f'../models/model_{i}.pkl')

if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    main()
EOF

    cat << 'EOF' > /app/text_prep_serve/src/server.py
from fastapi import FastAPI
from pydantic import BaseModel
import joblib
import os
import uvicorn
from collections import Counter

app = FastAPI()

class Item(BaseModel):
    text: str

@app.on_event("startup")
def load_models():
    global vectorizer, models
    base_dir = os.path.dirname(os.path.abspath(__file__))
    vectorizer = joblib.load(os.path.join(base_dir, '../models/vectorizer.pkl'))
    models = []
    for i in range(3):
        models.append(joblib.load(os.path.join(base_dir, f'../models/model_{i}.pkl')))

@app.post("/predict")
def predict(item: Item):
    X = vectorizer.transform([item.text])
    preds = [int(model.predict(X)[0]) for model in models]
    majority = Counter(preds).most_common(1)[0][0]
    return {"prediction": majority}

if __name__ == '__main__':
    uvicorn.run(app, host='127.0.0.1', port=8000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
