#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gawk jq
    pip3 install --default-timeout=100 pytest flask pandas scikit-learn joblib

    mkdir -p /app/services

    # Create Data API
    cat << 'EOF' > /app/services/data_api.py
import random
from flask import Flask, Response

app = Flask(__name__)

@app.route('/raw_data', methods=['GET'])
def raw_data():
    # Generate some data with issues
    random.seed(42)
    lines = ["id,age,income,activity_score,target"]
    for i in range(1, 1001):
        age = random.randint(18, 80)
        income = random.randint(20000, 150000)
        activity_score = random.uniform(0, 10)
        target = 5.0 + 0.1 * age + 0.0001 * income + 2.0 * activity_score + random.uniform(-2, 2)

        # Introduce issues
        if random.random() < 0.05:
            age = ""
        if random.random() < 0.05:
            income = ""
        if random.random() < 0.02:
            income = random.randint(300001, 500000) # Outlier

        lines.append(f"{i},{age},{income},{activity_score},{target}")

    return Response("\n".join(lines), mimetype='text/csv')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

    # Create Train API (with bug)
    cat << 'EOF' > /app/services/train_api.py
import os
import pandas as pd
from flask import Flask, request, jsonify
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error
import joblib

app = Flask(__name__)

@app.route('/train', methods=['POST'])
def train():
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    df = pd.read_csv(file)

    # Simple validation
    if df.isnull().values.any():
        return jsonify({"error": "Data contains missing values"}), 400

    X = df[['age', 'income', 'activity_score']]
    y = df['target']

    model = LinearRegression()
    model.fit(X, y)

    preds = model.predict(X)
    rmse = mean_squared_error(y, preds, squared=False)

    save_path = os.environ.get('MODEL_SAVE_PATH', '/tmp/model.joblib')
    joblib.dump(model, save_path)

    return jsonify({"message": "Model trained", "rmse": rmse})

if __name__ == '__main__':
    # BUG: Binding to a dummy host
    app.run(host='127.0.0.255', port=8001)
EOF

    # Create start script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nohup python3 /app/services/data_api.py > /tmp/data_api.log 2>&1 &
nohup python3 /app/services/train_api.py > /tmp/train_api.log 2>&1 &
echo "Services started."
EOF
    chmod +x /app/start_services.sh

    # Create hidden test data
    cat << 'EOF' > /app/hidden_test_data.py
import random
import pandas as pd

random.seed(99)
data = []
for i in range(1, 201):
    age = random.randint(18, 80)
    income = random.randint(20000, 150000)
    activity_score = random.uniform(0, 10)
    target = 5.0 + 0.1 * age + 0.0001 * income + 2.0 * activity_score + random.uniform(-2, 2)
    data.append([i, age, income, activity_score, target])

df = pd.DataFrame(data, columns=["id", "age", "income", "activity_score", "target"])
df.to_csv("/app/hidden_test_data.csv", index=False)
EOF
    python3 /app/hidden_test_data.py
    rm /app/hidden_test_data.py

    # Create verify_metric.py
    cat << 'EOF' > /app/verify_metric.py
import joblib
import pandas as pd
from sklearn.metrics import mean_squared_error
import os

if not os.path.exists("/home/user/model.joblib"):
    print("Model not found at /home/user/model.joblib")
    exit(1)

model = joblib.load("/home/user/model.joblib")
test_df = pd.read_csv("/app/hidden_test_data.csv")
X_test = test_df[['age', 'income', 'activity_score']]
y_test = test_df['target']
preds = model.predict(X_test)
rmse = mean_squared_error(y_test, preds, squared=False)

assert rmse <= 12.5, f"RMSE {rmse} is greater than threshold 12.5"

with open("/home/user/correlation.txt", "r") as f:
    corr = float(f.read().strip())
    assert -1.0 <= corr <= 1.0, f"Correlation {corr} is out of bounds"

print(f"METRIC_PASS: RMSE={rmse}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
