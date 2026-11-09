#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server curl procps
pip3 install pytest flask pandas numpy scikit-learn requests

mkdir -p /home/user/ml_pipeline/deploy

cat << 'EOF' > /home/user/ml_pipeline/data_api.py
from flask import Flask, send_file
import pandas as pd
import numpy as np

app = Flask(__name__)

@app.route('/download')
def download():
    # Generate synthetic data with a clear boundary but needing scaling
    np.random.seed(42)
    X = np.random.randn(2000, 5) * [10, 1, 0.1, 100, 5]
    y = (X[:, 0] * 0.5 + X[:, 1] * 2.0 - X[:, 3] * 0.01 > 0).astype(int)
    df = pd.DataFrame(X, columns=['f1', 'f2', 'f3', 'f4', 'f5'])
    df['target'] = y
    df.to_csv('/tmp/data.csv', index=False)
    return send_file('/tmp/data.csv')

if __name__ == '__main__':
    app.run(port=5000)
EOF

cat << 'EOF' > /home/user/ml_pipeline/inference_api.py
from flask import Flask, request, jsonify
import pickle
import numpy as np

app = Flask(__name__)

@app.route('/predict', methods=['POST'])
def predict():
    data = request.json
    try:
        with open('/home/user/ml_pipeline/deploy/model.pkl', 'rb') as f:
            model = pickle.load(f)
        X = np.array(data['features']).reshape(1, -1)
        pred = model.predict(X)[0]
        return jsonify({'prediction': int(pred)})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(port=5001)
EOF

cat << 'EOF' > /home/user/ml_pipeline/train.py
import argparse
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.metrics import accuracy_score
import pickle

parser = argparse.ArgumentParser()
parser.add_argument('--data', type=str, required=True)
parser.add_argument('--C', type=float, required=True)
args = parser.parse_args()

df = pd.read_csv(args.data)
X = df.drop('target', axis=1)
y = df['target']

# DATA LEAK HERE: Scaling before split
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_val, y_train, y_val = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

model = LogisticRegression(C=args.C, random_state=42)
model.fit(X_train, y_train)

preds = model.predict(X_val)
acc = accuracy_score(y_val, preds)

print(acc)

# Re-train on all data and save
model_full = LogisticRegression(C=args.C, random_state=42)
model_full.fit(X_scaled, y)

# Need to save the pipeline, but current code only saves the model, 
# which is another bug they must fix to properly serve inferences!
with open('model.pkl', 'wb') as f:
    # Actually, they need to save a Pipeline(steps=[('scaler', scaler), ('lr', model)])
    # We will leave this for them to figure out.
    pickle.dump(model_full, f)
EOF

cat << 'EOF' > /home/user/ml_pipeline/pipeline.sh
#!/bin/bash
# TODO: Download data, tune hyperparameters, and deploy
EOF
chmod +x /home/user/ml_pipeline/pipeline.sh

cat << 'EOF' > /home/user/ml_pipeline/serve.sh
#!/bin/bash
pkill -f inference_api.py
nohup python3 /home/user/ml_pipeline/inference_api.py > inference.log 2>&1 &
sleep 2
EOF
chmod +x /home/user/ml_pipeline/serve.sh

cat << 'EOF' > /home/user/verifier.py
import requests
import numpy as np

np.random.seed(999)
X = np.random.randn(1000, 5) * [10, 1, 0.1, 100, 5]
y = (X[:, 0] * 0.5 + X[:, 1] * 2.0 - X[:, 3] * 0.01 > 0).astype(int)

correct = 0
for i in range(1000):
    try:
        resp = requests.post('http://localhost:5001/predict', json={'features': X[i].tolist()})
        if resp.json().get('prediction') == y[i]:
            correct += 1
    except:
        pass

acc = correct / 1000.0
print(f"Accuracy: {acc}")
# Output the metric for the verifier framework
with open('/tmp/metric.txt', 'w') as f:
    f.write(str(acc))
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
