#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > train_data.csv
id,feature_1,feature_2,feature_3
t1,10.0,20.0,
t2,12.0,,15.0
t3,10.5,19.5,14.0
t4,9999.0,9999.0,9999.0
EOF

    cat << 'EOF' > query_data.csv
id,feature_1,feature_2,feature_3
q1,11.0,21.0,
q2,,19.0,14.5
EOF

    cat << 'EOF' > recommend.py
import pandas as pd
import numpy as np
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.metrics.pairwise import cosine_similarity
import json

train = pd.read_csv('train_data.csv')
query = pd.read_csv('query_data.csv')

# BUG: Data leakage!
combined = pd.concat([train, query])
features = combined[['feature_1', 'feature_2', 'feature_3']]

imputer = SimpleImputer(strategy='mean')
scaler = StandardScaler()

features_imputed = imputer.fit_transform(features)
features_scaled = scaler.fit_transform(features_imputed)

combined[['feature_1', 'feature_2', 'feature_3']] = features_scaled

train_processed = combined.iloc[:len(train)].copy()
query_processed = combined.iloc[len(train):].copy()

# Find top 1
results = {}
train_feats = train_processed[['feature_1', 'feature_2', 'feature_3']].values
query_feats = query_processed[['feature_1', 'feature_2', 'feature_3']].values

sim_matrix = cosine_similarity(query_feats, train_feats)
best_indices = np.argmax(sim_matrix, axis=1)

for i, q_row in enumerate(query.itertuples()):
    best_t_id = train.iloc[best_indices[i]]['id']
    results[q_row.id] = best_t_id

with open('recommendations.json', 'w') as f:
    json.dump(results, f, indent=2)
EOF

    cat << 'EOF' > track_experiment.sh
#!/bin/bash
echo "Logging experiment..."
cat recommendations.json >> experiment_log.json
EOF

    chmod +x track_experiment.sh

    chmod -R 777 /home/user
