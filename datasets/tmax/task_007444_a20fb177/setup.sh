#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_data.py
import pandas as pd
import numpy as np

# Readings Data
readings = pd.DataFrame({
    'Sensor_ID': ['S101', 'S102', 'S103', 'S104', 'S105'],
    't_0': [10.5, 5.1, -2.0, 15.0, 0.0],
    't_1': [11.0, 5.2, -2.1, 14.8, 0.1],
    't_2': [10.8, 4.9, -1.9, 15.2, -0.1],
    't_3': [11.2, 5.0, -2.2, 14.9, 0.2],
    't_4': [10.9, 5.1, -1.8, 15.1, 0.0]
})
readings.to_csv('/home/user/sensor_readings.csv', index=False, encoding='utf-16le')

# Metadata Data
metadata = pd.DataFrame({
    'Sensor_ID': ['S101', 'S102', 'S103', 'S104', 'S105'],
    'Zone': ['North', 'South', 'East', 'West', 'Center'],
    'Cal_Multiplier': [1.1, 0.9, 1.5, 0.95, 2.0],
    'Offset': [-0.5, 0.2, 1.0, -1.0, 5.0]
})
metadata.to_csv('/home/user/sensor_metadata.csv', index=False, encoding='iso-8859-1')

# Calculate expected results
df_r = readings.melt(id_vars='Sensor_ID', var_name='Time', value_name='Raw_Reading')
df_merged = pd.merge(df_r, metadata, on='Sensor_ID')
df_merged['Calibrated_Value'] = (df_merged['Raw_Reading'] * df_merged['Cal_Multiplier']) + df_merged['Offset']

# Group by and calculate L2 norm
result = df_merged.groupby('Sensor_ID')['Calibrated_Value'].apply(lambda x: np.sqrt(np.sum(x**2))).reset_index()
result.rename(columns={'Calibrated_Value': 'L2_Norm'}, inplace=True)

# Sort and format
result = result.sort_values(by=['L2_Norm', 'Sensor_ID'], ascending=[False, True])
result['L2_Norm'] = result['L2_Norm'].round(3).map('{:.3f}'.format)

result.to_csv('/home/user/.expected_norms.csv', index=False)
EOF

    python3 /home/user/create_data.py
    rm /home/user/create_data.py

    chmod -R 777 /home/user
