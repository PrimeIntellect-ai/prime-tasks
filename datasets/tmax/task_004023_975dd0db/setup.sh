#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make git
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    # Create skeleton C++ file
    cat << 'EOF' > /home/user/aggregate_throughput.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <map>
#include <vector>

// You will need to include simdjson
// #include "simdjson.h"

int main() {
    // TODO: Implement parsing and aggregation
    std::cout << "Not implemented yet." << std::endl;
    return 0;
}
EOF

    # Generate data and reference stats
    cat << 'EOF' > /tmp/generate_data.py
import json
import random
import pandas as pd
import numpy as np

random.seed(42)
locales = ['en-US', 'fr-FR', 'de-DE', 'es-ES', 'ja-JP']
start_ts = 1672531200 # 2023-01-01 00:00:00 UTC
end_ts = start_ts + 48 * 3600

events = []
for _ in range(500000):
    ts = random.randint(start_ts, end_ts)
    lang = random.choice(locales)
    words = random.randint(1, 100)
    events.append({"ts": ts, "lang": lang, "words": words})

events.sort(key=lambda x: x['ts'])

with open('/home/user/translation_events.jsonl', 'w') as f:
    for e in events:
        f.write(json.dumps(e) + '\n')

df = pd.DataFrame(events)
df['bucket_ts'] = df['ts'] - (df['ts'] % 3600)
hourly = df.groupby(['lang', 'bucket_ts'])['words'].sum().reset_index()
hourly.rename(columns={'words': 'hourly_words'}, inplace=True)

min_ts = hourly['bucket_ts'].min()
max_ts = hourly['bucket_ts'].max()
all_ts = np.arange(min_ts, max_ts + 3600, 3600)

grid = pd.MultiIndex.from_product([locales, all_ts], names=['lang', 'bucket_ts']).to_frame(index=False)
merged = pd.merge(grid, hourly, on=['lang', 'bucket_ts'], how='left').fillna({'hourly_words': 0})
merged.sort_values(['lang', 'bucket_ts'], inplace=True)

merged['rolling_3h_avg'] = merged.groupby('lang')['hourly_words'].transform(lambda x: x.rolling(3, min_periods=1).mean())

final = pd.merge(hourly[['lang', 'bucket_ts']], merged, on=['lang', 'bucket_ts'], how='left')
final.sort_values(['bucket_ts', 'lang'], inplace=True)
final['rolling_3h_avg'] = final['rolling_3h_avg'].round(2)

final.to_csv('/tmp/reference_stats.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    # Vendor simdjson
    mkdir -p /app
    cd /app
    git clone --depth 1 --branch v3.6.2 https://github.com/simdjson/simdjson.git
    cd simdjson

    # Perturb CMakeLists.txt
    sed -i '1s/^/set(CMAKE_CXX_STANDARD 11)\n/' CMakeLists.txt

    chmod -R 777 /app
    chmod -R 777 /home/user
