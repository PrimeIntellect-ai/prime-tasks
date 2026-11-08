#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy pyarrow fastparquet

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import os
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

def create_data():
    np.random.seed(42)
    locations = [f"LOC_{i:03d}" for i in range(1, 6)]
    base_time = datetime(2023, 1, 1)
    timestamps = [base_time + timedelta(hours=i) for i in range(24 * 30)] # 30 days

    os.makedirs("/home/user/raw_data/weather", exist_ok=True)
    os.makedirs("/home/user/raw_data/traffic", exist_ok=True)
    os.makedirs("/home/user/raw_data/air_quality", exist_ok=True)

    for loc in locations:
        n = len(timestamps)

        # Base independent variables
        temp = np.random.normal(15, 5, n)
        traffic = np.random.normal(500, 150, n)

        # Dependent variables with intentional correlations
        # humidity is negatively correlated with temp
        humidity = 100 - (temp * 2) + np.random.normal(0, 10, n)

        # no2 is highly correlated with traffic
        no2 = traffic * 0.08 + np.random.normal(0, 5, n)

        # pm25 is correlated with both temp and traffic
        pm25 = traffic * 0.03 - temp * 0.5 + np.random.normal(0, 8, n)

        # Clamp values
        humidity = np.clip(humidity, 0, 100)
        traffic = np.clip(traffic, 0, None)
        no2 = np.clip(no2, 0, None)
        pm25 = np.clip(pm25, 0, None)

        # Weather
        df_weather = pd.DataFrame({"timestamp": timestamps, "location_id": loc, "temperature": temp, "humidity": humidity})
        df_weather.to_csv(f"/home/user/raw_data/weather/{loc}_weather.csv", index=False)

        # Traffic
        df_traffic = pd.DataFrame({"timestamp": timestamps, "location_id": loc, "traffic_volume": traffic})
        df_traffic.to_csv(f"/home/user/raw_data/traffic/{loc}_traffic.csv", index=False)

        # Air Quality
        df_aq = pd.DataFrame({"timestamp": timestamps, "location_id": loc, "pm25": pm25, "no2": no2})
        df_aq.to_csv(f"/home/user/raw_data/air_quality/{loc}_aq.csv", index=False)

if __name__ == "__main__":
    create_data()
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
