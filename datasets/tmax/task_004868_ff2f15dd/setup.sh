#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error

np.random.seed(42)

# Generate batch 1
n1 = 100
sensor_ids_1 = np.random.randint(1, 4, n1)
temp_1 = np.random.uniform(10, 30, n1)
hum_1 = np.random.uniform(40, 80, n1)
# pressure = 10*temp + 0.5*hum + 1000 + noise
press_1 = 10 * temp_1 + 0.5 * hum_1 + 1000 + np.random.normal(0, 2, n1)

df1 = pd.DataFrame({'sensor_id': sensor_ids_1, 'temperature': temp_1, 'humidity': hum_1, 'pressure': press_1})
df1.to_csv('/home/user/data/batch_1.csv', index=False)

# Generate batch 2
n2 = 150
sensor_ids_2 = np.random.randint(2, 6, n2)
temp_2 = np.random.uniform(5, 25, n2)
hum_2 = np.random.uniform(30, 90, n2)
press_2 = 10 * temp_2 + 0.5 * hum_2 + 1000 + np.random.normal(0, 2.5, n2)

df2 = pd.DataFrame({'sensor_id': sensor_ids_2, 'temperature': temp_2, 'humidity': hum_2, 'pressure': press_2})
df2.to_csv('/home/user/data/batch_2.csv', index=False)

# Ground truth calculation
df_combined = pd.concat([df1, df2])

# Aggregation truth
agg = df_combined.groupby('sensor_id')['temperature'].mean().reset_index()
agg.rename(columns={'temperature': 'avg_temperature'}, inplace=True)
agg['avg_temperature'] = agg['avg_temperature'].round(2)
agg.sort_values('sensor_id').to_csv('/home/user/expected_agg_results.csv', index=False)

# Regression truth
X = df_combined[['temperature', 'humidity']]
y = df_combined['pressure']
model = LinearRegression()
model.fit(X, y)
preds = model.predict(X)
rmse = np.sqrt(mean_squared_error(y, preds))

with open('/home/user/expected_model_metrics.txt', 'w') as f:
    f.write(f"{rmse:.4f}\n")

EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
