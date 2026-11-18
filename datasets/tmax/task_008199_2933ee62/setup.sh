#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn matplotlib

    useradd -m -s /bin/bash user || true

    # Create data.csv
    python3 -c "
import pandas as pd
import numpy as np

np.random.seed(42)
x1 = np.random.rand(100)
x2 = np.random.rand(100)
y = 3.5 * x1 + 2.1 * x2 + np.random.randn(100) * 0.5

df = pd.DataFrame({'x1': x1, 'x2': x2, 'y': y})
df.to_csv('/home/user/data.csv', index=False)
"

    # Create experiment.py
    cat << 'EOF' > /home/user/experiment.py
import pandas as pd
import numpy as np
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# Load data
df = pd.read_csv('/home/user/data.csv')

# Schema enforcement - BUG: y is cast to int instead of float
schema = {'x1': float, 'x2': float, 'y': int}
df = df.astype(schema)

# CV and tuning
model = Ridge()
param_grid = {'alpha': [0.1, 1.0, 10.0]}
grid = GridSearchCV(model, param_grid, cv=5, scoring='neg_mean_squared_error')
grid.fit(df[['x1', 'x2']], df['y'])

# Save best score
with open('/home/user/best_score.txt', 'w') as f:
    f.write(f"{-grid.best_score_:.4f}")

# Plot results
plt.plot([0.1, 1.0, 10.0], -grid.cv_results_['mean_test_score'], marker='o')
plt.title('CV Results')
plt.xlabel('Alpha')
plt.ylabel('MSE')

# BUG: Clears figure before saving
plt.clf()
plt.savefig('/home/user/results.png')
EOF

    chmod -R 777 /home/user
