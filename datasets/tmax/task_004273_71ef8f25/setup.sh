#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

def generate():
    np.random.seed(42)
    n_samples = 2000

    # Feature 1: Very large scale (e.g., pressure in Pascals)
    X1 = np.random.uniform(10000, 50000, n_samples)

    # Feature 2: Very small scale (e.g., friction coefficient)
    X2 = np.random.uniform(0.001, 0.005, n_samples)

    # Target variable
    y = 0.05 * X1 + 15000 * X2 + np.random.normal(0, 10, n_samples)

    df = pd.DataFrame({'pressure': X1, 'friction': X2, 'target': y})
    df.to_csv('/home/user/data.csv', index=False)
    print("Data generated at /home/user/data.csv")

if __name__ == "__main__":
    generate()
EOF

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
import numpy as np
import json
import matplotlib.pyplot as plt
from sklearn.model_selection import train_test_split
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_absolute_error

def main():
    # 1. Extract
    df = pd.read_csv('/home/user/data.csv')
    X = df[['pressure', 'friction']]
    y = df['target']

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    # 2. Transform & Model (BUG: Needs scaling, Ridge fails terribly on unscaled features)
    model = Ridge(alpha=1.0)
    model.fit(X_train, y_train)

    predictions = model.predict(X_test)
    mae = mean_absolute_error(y_test, predictions)
    print(f"Validation MAE: {mae}")

    # Write metrics (Agent needs to add this)
    # with open('/home/user/metrics.json', 'w') as f:
    #     json.dump({"mae": mae}, f)

    # 3. Diagnostic Plot (BUG: plt.show() clears the figure before savefig)
    plt.figure(figsize=(8, 6))
    plt.scatter(y_test, predictions, alpha=0.5)
    plt.xlabel('True Values')
    plt.ylabel('Predictions')
    plt.title('Residuals')

    plt.show() # This consumes the current figure
    plt.savefig('/home/user/residuals.png') # Saves a blank image

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
