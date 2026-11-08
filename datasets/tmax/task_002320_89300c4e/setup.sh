#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    python3 -c '
import pandas as pd
import numpy as np
import os

dates = pd.date_range(start="2023-01-01", end="2023-12-31", freq="D")
df = pd.DataFrame({"Date": dates.strftime("%Y-%m-%d")})

np.random.seed(123)
# S1: Perfect data
df["S1_T"] = np.random.uniform(10, 30, size=len(dates))
df["S1_H"] = np.random.uniform(40, 80, size=len(dates))

# S2: Invalid temp (Rule A violation)
df["S2_T"] = np.random.uniform(10, 30, size=len(dates))
df.loc[150, "S2_T"] = 65.0 # > 60
df["S2_H"] = np.random.uniform(40, 80, size=len(dates))

# S3: Perfect data
df["S3_T"] = np.random.uniform(-10, 20, size=len(dates))
df["S3_H"] = np.random.uniform(30, 90, size=len(dates))

# S4: Missing > 5% THI (Rule B violation - 20 missing > 18.25)
df["S4_T"] = np.random.uniform(10, 30, size=len(dates))
df["S4_H"] = np.random.uniform(40, 80, size=len(dates))
missing_idx = np.random.choice(len(dates), size=20, replace=False)
df.loc[missing_idx, "S4_H"] = np.nan

df.to_csv("/home/user/sensor_data.csv", index=False)
'

    chmod -R 777 /home/user
