#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn Pillow numpy

    # Create directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate data and image
    python3 -c '
import os
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw

# Generate image
img = Image.new("RGB", (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """Inference Anomaly Rules:
1. Impute missing values using the median of each column.
2. Standardize features (latency_ms, memory_mb, cpu_util) using StandardScaler.
3. Apply PCA to reduce these 3 features to 1 principal component.
4. If the maximum absolute value of the 1st principal component across all rows strictly exceeds 2.85, the log is UNSTABLE."""
d.text((10,10), text, fill=(0,0,0))
img.save("/app/criteria.png")

np.random.seed(42)

# Generate clean data
for i in range(5):
    df = pd.DataFrame({
        "timestamp": pd.date_range("2023-01-01", periods=50),
        "model_id": ["model_A"]*50,
        "latency_ms": np.random.normal(100, 5, 50),
        "memory_mb": np.random.normal(500, 20, 50),
        "cpu_util": np.random.normal(40, 2, 50)
    })
    # introduce some missing values
    df.loc[5, "latency_ms"] = np.nan
    df.to_csv(f"/app/corpora/clean/clean_{i}.csv", index=False)

# Generate evil data
for i in range(5):
    df = pd.DataFrame({
        "timestamp": pd.date_range("2023-01-01", periods=50),
        "model_id": ["model_B"]*50,
        "latency_ms": np.random.normal(100, 5, 50),
        "memory_mb": np.random.normal(500, 20, 50),
        "cpu_util": np.random.normal(40, 2, 50)
    })
    # inject anomaly to ensure PCA component > 2.85
    df.loc[25, "latency_ms"] = 300
    df.loc[25, "memory_mb"] = 1500
    df.loc[25, "cpu_util"] = 95
    df.to_csv(f"/app/corpora/evil/evil_{i}.csv", index=False)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
