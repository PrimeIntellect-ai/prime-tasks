#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/articles.csv
id,title,text
1,AI Basics,Artificial intelligence and machine learning.
2,Neural Nets,Deep learning and neural networks are powerful.
3,Python,Python is a programming language.
4,Data Science,Statistics and data science.
bad,Bad Row,This has a bad id.
6,Cooking,Baking a cake in the oven.
7,More AI,Machine learning applications and deep learning.
8,Data Eng,Data engineering and pipelines.
9,Missing Text,
10,NLP,Natural language processing with neural networks.
EOF

    cat << 'EOF' > /home/user/recommend.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import train_test_split
from sklearn.metrics.pairwise import cosine_similarity
import json

df = pd.read_csv('/home/user/data/articles.csv')

# BUG: Data leak and no schema validation
vectorizer = TfidfVectorizer()
X = vectorizer.fit_transform(df['text'])

X_train, X_test = train_test_split(X, test_size=0.25, random_state=42)

train_sim = cosine_similarity(X_train).mean()
test_sim = cosine_similarity(X_test).mean()

with open('/home/user/metrics.json', 'w') as f:
    json.dump({"train_avg_sim": train_sim, "test_avg_sim": test_sim}, f)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
