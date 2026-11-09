#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest pandas numpy gTTS

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /home/user/samples

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
import pandas as pd
from gtts import gTTS
import subprocess

# Generate Audio
text = "Hello data team. Here are the strict rejection rules for our incoming sensor datasets. You must reject the file if any of the following three conditions are met. Condition one: If any value in the 'temperature' column is exactly 999.9. Condition two: If the 'status' column contains any missing or null values. Condition three: You must calculate the 95th percentile of the 'pressure' column using a bootstrap method. Specifically, draw exactly one thousand bootstrap samples of the pressure column, using a random state or seed of 42. Calculate the 95th percentile of the original pressure data using numpy's default percentile function, but wait, the rule is to just calculate the 95th percentile of the *original* pressure column? No, sorry, let me correct that: take the 1000 bootstrap sample means of the pressure column using seed 42. If the maximum pressure value in the dataset exceeds the 95th percentile of those 1000 bootstrap means by strictly more than 10 units, reject the file. Otherwise, accept it."
tts = gTTS(text)
tts.save('/app/guidelines.mp3')
subprocess.run(['ffmpeg', '-y', '-i', '/app/guidelines.mp3', '/app/guidelines.wav'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
os.remove('/app/guidelines.mp3')

# Generate Datasets
def generate_base_df():
    n = 100
    temp = np.random.uniform(20.0, 30.0, n)
    status = np.random.choice(['active', 'inactive', 'maintenance'], n)
    pressure = np.random.normal(100.0, 5.0, n)
    return pd.DataFrame({'temperature': temp, 'status': status, 'pressure': pressure})

def get_p95_bootstrap(pressure_values):
    np.random.seed(42)
    n = len(pressure_values)
    means = [np.mean(np.random.choice(pressure_values, size=n, replace=True)) for _ in range(1000)]
    return np.percentile(means, 95)

# Clean
for i in range(10):
    np.random.seed(i)
    df = generate_base_df()
    p95 = get_p95_bootstrap(df['pressure'].values)
    # Ensure max pressure is safely below threshold
    df.loc[df['pressure'] > p95 + 5, 'pressure'] = p95
    df.to_csv(f'/app/corpora/clean/clean_{i}.csv', index=False)

# Evil 1: temp = 999.9
for i in range(5):
    np.random.seed(100 + i)
    df = generate_base_df()
    df.loc[10, 'temperature'] = 999.9
    df.to_csv(f'/app/corpora/evil/evil_temp_{i}.csv', index=False)

# Evil 2: status NaN
for i in range(5):
    np.random.seed(200 + i)
    df = generate_base_df()
    df.loc[20, 'status'] = np.nan
    df.to_csv(f'/app/corpora/evil/evil_status_{i}.csv', index=False)

# Evil 3: pressure spike
for i in range(5):
    np.random.seed(300 + i)
    df = generate_base_df()
    p95 = get_p95_bootstrap(df['pressure'].values)
    df.loc[30, 'pressure'] = p95 + 10.5
    df.to_csv(f'/app/corpora/evil/evil_pressure_{i}.csv', index=False)

# Sample for user
df_sample = generate_base_df()
df_sample.to_csv('/home/user/samples/sample.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
