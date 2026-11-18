#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy matplotlib

    mkdir -p /home/user
    cd /home/user

    python3 -c "
import numpy as np
import pandas as pd
np.random.seed(10)
data = np.random.normal(loc=100, scale=15, size=100)
data[5] = np.nan
data[20] = np.nan
data[50] = np.nan
pd.DataFrame({'value': data}).to_csv('/home/user/data.csv', index=False)
"

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('TkAgg') # Bug 1: Will crash in headless environment
import matplotlib.pyplot as plt

def bootstrap_mean(data, n_iterations=1000):
    means = []
    for _ in range(n_iterations):
        sample = np.random.choice(data, size=len(data), replace=True)
        means.append(np.mean(sample))
    return np.percentile(means, [2.5, 50, 97.5])

def run_pipeline():
    df = pd.read_csv('/home/user/data.csv')
    feature = df['value'].values

    # Bug 2: Missing values are not handled, causing NaN propagation

    np.random.seed(42)
    ci_lower, mean_val, ci_upper = bootstrap_mean(feature)

    # Reconstructed Model (y = 3.2 * x_scaled + 1.5)
    # Bug 3: Input is not standardized
    pred = 3.2 * mean_val + 1.5

    # Plot
    plt.hist(feature, bins=20)
    plt.axvline(mean_val, color='r')
    plt.savefig('/home/user/output_plot.png')

    with open('/home/user/metrics.txt', 'w') as f:
        f.write(f"Mean: {mean_val:.2f}\n")
        f.write(f"CI: {ci_lower:.2f}-{ci_upper:.2f}\n")
        f.write(f"Prediction: {pred:.2f}\n")

if __name__ == '__main__':
    run_pipeline()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
