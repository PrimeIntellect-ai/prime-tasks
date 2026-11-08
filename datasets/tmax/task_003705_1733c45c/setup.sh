#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        g++ \
        make \
        cmake

    pip3 install pytest pandas numpy pillow

    mkdir -p /app

    cat << 'EOF' > /app/setup.py
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw

# Generate Config Image
img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
d.text((10, 50), "BucketSize: 300", fill=(0, 0, 0))
d.text((10, 100), "ZThreshold: 3.0", fill=(0, 0, 0))
img.save('/app/sensor_config.png')

# Generate Sensor Data
num_rows = 100000
num_sensors = 100
np.random.seed(42)

timestamps = np.arange(1700000000, 1700000000 + num_rows)
data = np.random.randn(num_rows, num_sensors)

# Inject anomalies
anomaly_mask = np.random.rand(num_rows, num_sensors) < 0.005
data[anomaly_mask] += np.sign(data[anomaly_mask]) * 5.0 

df = pd.DataFrame(data, columns=[f"sensor_{i}" for i in range(num_sensors)])
df.insert(0, "timestamp", timestamps)
df.to_csv("/app/sensor_data.csv", index=False)

# Generate Ground Truth
bucket_size = 300
z_threshold = 3.0

df_long = df.melt(id_vars=["timestamp"], var_name="sensor_id", value_name="value")
df_long["bucket_start_time"] = (df_long["timestamp"] // bucket_size) * bucket_size

mean = df_long.groupby(["bucket_start_time", "sensor_id"])["value"].transform("mean")
std = df_long.groupby(["bucket_start_time", "sensor_id"])["value"].transform("std")
df_long["is_anomaly"] = np.abs(df_long["value"] - mean) > (z_threshold * std)

anomalies = df_long[df_long["is_anomaly"]]
truth = anomalies.groupby(["bucket_start_time", "sensor_id"]).size().reset_index(name="anomaly_count")
truth = truth.sort_values(["bucket_start_time", "sensor_id"])
truth.to_csv("/app/truth_anomalies.csv", index=False)
EOF

    python3 /app/setup.py
    rm /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
