#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
id,group,text
1,Control,machine learning models need careful tuning
2,Control,data pipelines extract transform and load
3,Control,automated processes save time
4,Control,we build models for data science
5,Control,pipelines are crucial for engineering
6,Treatment,automated machine learning pipelines are the future
7,Treatment,automl pipelines improve efficiency
8,Treatment,machine learning automation is key
9,Treatment,building pipelines for automated learning
10,Treatment,we love automated machine learning pipelines
EOF

    cat << 'EOF' > /home/user/evaluate.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from scipy import stats
import json

df = pd.read_csv('/home/user/data.csv')
query = "automated machine learning pipelines"

# THE LEAK: Fitting on the entire dataset
vectorizer = TfidfVectorizer()
X = vectorizer.fit_transform(df['text'])
query_vec = vectorizer.transform([query])

similarities = cosine_similarity(X, query_vec).flatten()
df['sim'] = similarities

control_sims = df[df['group'] == 'Control']['sim']
treatment_sims = df[df['group'] == 'Treatment']['sim']

# T-test
t_stat, p_val = stats.ttest_ind(control_sims, treatment_sims, equal_var=False)

with open('/home/user/results_leak.json', 'w') as f:
    json.dump({"t": t_stat, "p": p_val}, f)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
