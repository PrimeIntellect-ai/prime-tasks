#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk
pip3 install --no-cache-dir pytest numpy pandas scikit-learn

mkdir -p /home/user/experiment
cd /home/user/experiment

cat << 'EOF' > make_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
# 100 rows. 80 train, 20 test.
f1 = np.random.normal(10, 2, 100)
f2 = np.random.normal(5, 1, 100)

# True relationship: target = 3*f1 + 2*f2 + noise
target = 3*f1 + 2*f2 + np.random.normal(0, 0.5, 100)

# Introduce an extreme outlier in the test set to make the scaler leak very obvious
f1[95] = 1000  

df = pd.DataFrame({'feature1': f1, 'feature2': f2, 'target': target})
df.to_csv('data.csv', index=False)
EOF

python3 make_data.py
rm make_data.py

cat << 'EOF' > train.py
import pandas as pd
from sklearn.preprocessing import MinMaxScaler
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression
import numpy as np

# Load data
df = pd.read_csv('data.csv')
X = df[['feature1', 'feature2']]
y = df['target']

# DATA LEAK: Scaling before splitting! 
# The MinMaxScaler sees the outlier at index 95 and squashes all training data.
scaler = MinMaxScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, shuffle=False)

model = LinearRegression()
model.fit(X_train, y_train)

preds = model.predict(X_test)
np.savetxt('leaky_predictions.csv', preds, fmt='%.6f')
EOF

python3 train.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
