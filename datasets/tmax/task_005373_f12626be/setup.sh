#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn matplotlib

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    # Create sensor_A.csv
    cat << 'EOF' > sensor_A.csv
id,temp,pressure
1,20.5,1010
2,21.0,1012
3,150.0,1008
4,19.5,1015
5,22.1,1011
EOF

    # Create sensor_B.csv
    cat << 'EOF' > sensor_B.csv
id,humidity
1,45.0
2,46.5
3,40.0
4,
5,48.0
EOF

    # Create broken analysis.py
    cat << 'EOF' > analysis.py
import pandas as pd
from sklearn.linear_model import LinearRegression
import matplotlib.pyplot as plt
import json

# Read data
df_a = pd.read_csv('sensor_A.csv')
df_b = pd.read_csv('sensor_B.csv')

# TODO: Join on id
df = pd.concat([df_a, df_b])

# TODO: Handle missing humidity

# TODO: Remove outliers (temp > 50)

# Train model
X = df[['pressure', 'humidity']]
y = df['temp']
model = LinearRegression()
model.fit(X, y)

# Save results
results = {
    "pressure_coef": round(model.coef_[0], 4),
    "humidity_coef": round(model.coef_[1], 4),
    "intercept": round(model.intercept_, 4)
}
with open('model_results.json', 'w') as f:
    json.dump(results, f)

# Plot
preds = model.predict(X)
plt.scatter(y, preds)
plt.xlabel('True Temp')
plt.ylabel('Predicted Temp')
plt.show() # This causes issues on headless servers
plt.savefig('predictions.png')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
