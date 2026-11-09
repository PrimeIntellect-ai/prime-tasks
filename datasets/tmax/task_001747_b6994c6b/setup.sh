#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    # Create the dummy data
    cat << 'EOF' > /tmp/create_data.py
import numpy as np
import pandas as pd

np.random.seed(100)
X1 = np.random.normal(10, 2, 1000)
X2 = np.random.normal(5, 1, 1000)
y = 3 * X1 + 1.5 * X2 + np.random.normal(0, 1, 1000)

df = pd.DataFrame({'feature_1': X1, 'feature_2': X2, 'target': y})
df.to_csv('/home/user/data.csv', index=False)
EOF
    python3 /tmp/create_data.py

    # Create the buggy script
    cat << 'EOF' > /home/user/etl_validation.py
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import json
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error

def main():
    # Load data
    df = pd.read_csv('/home/user/data.csv')

    # 1. Bootstrap sampling for target mean
    np.random.seed(42)
    n_iterations = 1000
    bootstrap_means = []

    for _ in range(n_iterations):
        # BUG: replace=False invalidates the bootstrap
        sample = np.random.choice(df['target'], size=len(df), replace=False)
        bootstrap_means.append(np.mean(sample))

    bootstrap_mean = float(np.mean(bootstrap_means))
    ci_lower = float(np.percentile(bootstrap_means, 2.5))
    ci_upper = float(np.percentile(bootstrap_means, 97.5))

    # 2. Train baseline model and evaluate
    model = LinearRegression()
    X = df[['feature_1', 'feature_2']]
    y = df['target']

    model.fit(X, y)
    preds = model.predict(X)
    mse = float(mean_squared_error(y, preds))

    # 3. Save plot (BUG: No Agg backend set for headless environment)
    plt.hist(bootstrap_means, bins=30)
    plt.title('Bootstrap Distribution')
    plt.savefig('/home/user/bootstrap_dist.png')

    # 4. Save metrics
    metrics = {
        "bootstrap_mean": bootstrap_mean,
        "ci_lower": ci_lower,
        "ci_upper": ci_upper,
        "model_mse": mse
    }

    with open('/home/user/metrics.json', 'w') as f:
        json.dump(metrics, f, indent=4)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
