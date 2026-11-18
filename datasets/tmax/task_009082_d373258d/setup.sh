#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy matplotlib

    useradd -m -s /bin/bash user || true

    # Create sensor_data.csv
    python3 -c "
import numpy as np
import pandas as pd

np.random.seed(42)
X = np.random.normal(0, 5, 1000)
# Add NaNs
X[np.random.choice(1000, 50, replace=False)] = np.nan
# Add Outliers
X[np.random.choice(1000, 20, replace=False)] = 50.0
X[np.random.choice(1000, 20, replace=False)] = -50.0

df = pd.DataFrame({'X': X})
df.to_csv('/home/user/sensor_data.csv', index=False)
"

    # Create model_weights.json
    cat << 'EOF' > /home/user/model_weights.json
{
  "W1": [[2.0, -1.0]],
  "b1": [0.5, 0.0],
  "W2": [[1.5], [0.5]],
  "b2": [-1.0]
}
EOF

    # Create the broken script etl_pipeline.py
    cat << 'EOF' > /home/user/etl_pipeline.py
import pandas as pd
import numpy as np
import json
import time
import matplotlib.pyplot as plt

def load_weights(path):
    with open(path, 'r') as f:
        w = json.load(f)
    return {k: np.array(v) for k, v in w.items()}

def predict(X, weights):
    # X is shape (N, 1)
    # Layer 1
    H = np.dot(X, weights['W1']) + weights['b1']

    # TODO: Apply activation function here (ReLU)

    # Layer 2
    Y = np.dot(H, weights['W2']) + weights['b2']
    return Y

def main():
    # 1. Load data
    df = pd.DataFrame({'X': []}) # TODO: Load actual data

    # TODO: Clean data (Impute median, clip between -10 and 10)
    median_val = 0.0
    X_clean = df[['X']].values

    weights = load_weights('/home/user/model_weights.json')

    # 2 & 3. Run inference and benchmark
    start_time = time.time()
    predictions = predict(X_clean, weights)
    end_time = time.time()

    inference_time = end_time - start_time
    mean_pred = float(np.mean(predictions)) if len(predictions) > 0 else 0.0

    # 4. Plotting
    plt.scatter(X_clean, predictions)
    plt.title("Sensor Predictions")
    # plt.show() # This crashes in headless!

    # Save metrics
    metrics = {
        "median_imputed": median_val,
        "mean_prediction": mean_pred,
        "inference_time_seconds": inference_time
    }
    with open('/home/user/pipeline_metrics.json', 'w') as f:
        json.dump(metrics, f, indent=4)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
