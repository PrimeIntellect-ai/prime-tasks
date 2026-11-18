#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest pandas numpy

    mkdir -p /home/user
    cd /home/user

    # Generate the CSV data
    cat << 'EOF' > generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
lr_A = np.random.uniform(0.001, 0.1, 25)
val_loss_A = 0.5 - 2 * lr_A + np.random.normal(0, 0.05, 25)

lr_B = np.random.uniform(0.001, 0.1, 25)
val_loss_B = 0.6 - 1.5 * lr_B + np.random.normal(0, 0.05, 25)

df = pd.DataFrame({
    'experiment_id': range(1, 51),
    'learning_rate': np.concatenate([lr_A, lr_B]),
    'architecture': ['Arch_A']*25 + ['Arch_B']*25,
    'val_loss': np.concatenate([val_loss_A, val_loss_B])
})
df.to_csv('experiments.csv', index=False)
EOF
    python3 generate_data.py
    rm generate_data.py

    # Create the broken script
    cat << 'EOF' > generate_report.py
import pandas as pd
import matplotlib.pyplot as plt
import scipy.stats as stats
import json
import os

def main():
    df = pd.read_csv('/home/user/experiments.csv')

    # 1. Plotting (Currently broken in headless environments)
    plt.scatter(df['learning_rate'], df['val_loss'])
    plt.title('Learning Rate vs Val Loss')
    plt.xlabel('Learning Rate')
    plt.ylabel('Validation Loss')
    # BUG: plt.show() will fail in headless. Needs backend fix and savefig.
    plt.show() 

    # 2. Correlation Analysis
    # TODO: Calculate Pearson correlation and p-value between learning_rate and val_loss
    corr_coef = 0.0
    corr_p_val = 0.0

    # 3. Hypothesis Testing
    # TODO: Calculate independent t-test (equal variance) for val_loss of Arch_A vs Arch_B
    t_stat = 0.0
    t_p_val = 0.0

    # 4. Save results
    results = {
        "correlation_coefficient": round(corr_coef, 4),
        "correlation_p_value": round(corr_p_val, 4),
        "t_statistic": round(t_stat, 4),
        "t_test_p_value": round(t_p_val, 4)
    }

    with open('/home/user/report.json', 'w') as f:
        json.dump(results, f, indent=4)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
