#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /home/user/train_model.py
import pandas as pd
from sklearn.linear_model import LinearRegression

# Load data
df = pd.read_csv('/home/user/equipment_stats.csv')

# Calculate correlation (will fail/return NaN due to missing values)
corr = df['temp'].corr(df['pressure'])

# Train model (will crash due to NaNs and outliers ruining the fit)
model = LinearRegression()
model.fit(df[['temp', 'pressure']], df['vibration'])

print("Correlation:", corr)
print("Coefficients:", model.coef_)
EOF

    cat << 'EOF' > /home/user/equipment_stats.csv
temp,pressure,vibration
20.5,101.2,5.1
22.1,,5.5
21.0,100.8,5.0
999.0,105.0,20.0
23.5,101.5,5.8
24.0,102.0,6.1
22.8,101.0,5.6
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
