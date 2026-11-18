#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask redis pandas scikit-learn numpy joblib requests category_encoders

    mkdir -p /app
    mkdir -p /home/user

    # Setup script to generate data
    cat << 'EOF' > /app/setup.py
import pandas as pd
import numpy as np
import json

np.random.seed(42)
n_samples = 1000

categories = ['electronics', 'clothing', 'home', 'toys', 'books']
cat_baselines = {'electronics': 200, 'clothing': 50, 'home': 100, 'toys': 30, 'books': 20}

data = []
for _ in range(n_samples):
    cat = np.random.choice(categories)
    desc = f"Great {cat} product with excellent features and durable build."
    price = cat_baselines[cat] + np.random.normal(0, 10)
    data.append({'description': desc, 'category': cat, 'price': price})

df = pd.DataFrame(data)
with open('/app/api_data.json', 'w') as f:
    json.dump(df.to_dict(orient='records'), f)

hidden_data = []
for _ in range(300):
    cat = np.random.choice(categories)
    desc = f"New {cat} release, very cool and standard."
    price = cat_baselines[cat] + np.random.normal(0, 10)
    hidden_data.append({'description': desc, 'category': cat, 'price': price})

pd.DataFrame(hidden_data).to_csv('/app/hidden_data.csv', index=False)
EOF

    python3 /app/setup.py

    # Flask API script
    cat << 'EOF' > /app/api.py
from flask import Flask, jsonify
import json

app = Flask(__name__)

@app.route('/data')
def get_data():
    with open('/app/api_data.json', 'r') as f:
        data = json.load(f)
    return jsonify(data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Services startup script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/api.py &
sleep 2
EOF
    chmod +x /app/start_services.sh

    # Initial broken ETL pipeline script
    cat << 'EOF' > /home/user/etl_pipeline.py
import requests
import redis
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import TruncatedSVD
from sklearn.linear_model import Ridge
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error
import joblib

# Connect to Redis (Intentional error: wrong port)
try:
    r = redis.Redis(host='localhost', port=6380)
    # r.set('pipeline_status', 'success')
except Exception as e:
    print("Redis connection failed:", e)

# Fetch data from API (Intentional error: wrong port)
response = requests.get('http://127.0.0.1:5001/data')
data = response.json()

df = pd.DataFrame(data)

# Intentional Data Leakage: fit_transform on the entire dataset before split
tfidf = TfidfVectorizer()
svd = TruncatedSVD(n_components=2)
text_features = svd.fit_transform(tfidf.fit_transform(df['description']))

# Target Encoding Leakage
means = df.groupby('category')['price'].mean()
df['cat_encoded'] = df['category'].map(means)

X = pd.concat([pd.DataFrame(text_features), df['cat_encoded']], axis=1)
X.columns = [str(c) for c in X.columns]
y = df['price']

# Split data
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# Train model
model = Ridge()
model.fit(X_train, y_train)

# Evaluate locally
preds = model.predict(X_test)
print("Local MAE:", mean_absolute_error(y_test, preds))

# Save model
joblib.dump(model, '/home/user/final_pipeline.pkl')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
