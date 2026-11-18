#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest pandas numpy

    mkdir -p /app
    mkdir -p /home/user
    mkdir -p /tmp

    cat << 'EOF' > /tmp/score_activity.cpp
#include <iostream>
#include <cstdlib>
#include <iomanip>
#include <algorithm>

int main(int argc, char* argv[]) {
    if (argc != 6) return 1;
    double age = std::atof(argv[1]);
    double loc = std::atof(argv[2]);
    double clicks = std::atof(argv[3]);
    double imps = std::atof(argv[4]);
    double dur = std::atof(argv[5]);

    double denom = imps > 1.0 ? imps : 1.0;
    int loc_mod = static_cast<int>(loc) % 10;

    double score = (age * 0.5) + (loc_mod * 2.0) + ((clicks / denom) * 100.0) + (dur * 0.01);

    std::cout << std::fixed << std::setprecision(4) << score << std::endl;
    return 0;
}
EOF

    g++ -O3 /tmp/score_activity.cpp -o /app/score_activity
    strip -s /app/score_activity
    chmod +x /app/score_activity

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
N_USERS = 100000

uids = np.arange(1, N_USERS + 1)
ages = np.random.randint(18, 80, size=N_USERS)
locs = np.random.randint(100, 999, size=N_USERS)

demographics = pd.DataFrame({'uid': uids, 'age': ages, 'location_code': locs})
demographics.to_csv('/home/user/demographics.csv', index=False)

N_ACTIVITY = 300000
act_uids = np.random.choice(uids, size=N_ACTIVITY, replace=True)
clicks = np.random.randint(0, 10, size=N_ACTIVITY)
imps = clicks + np.random.randint(1, 50, size=N_ACTIVITY)
dur = np.random.uniform(5.0, 300.0, size=N_ACTIVITY)

activity = pd.DataFrame({'uid': act_uids, 'clicks': clicks, 'impressions': imps, 'duration_sec': dur})
activity.to_csv('/home/user/activity.csv', index=False)

agg = activity.groupby('uid').sum().reset_index()
df = pd.merge(demographics, agg, on='uid', how='left').fillna(0)

denom = np.where(df['impressions'] > 1.0, df['impressions'], 1.0)
loc_mod = df['location_code'].astype(int) % 10
df['score'] = (df['age'] * 0.5) + (loc_mod * 2.0) + ((df['clicks'] / denom) * 100.0) + (df['duration_sec'] * 0.01)

df = df.sort_values('uid')
df[['uid', 'score']].to_csv('/tmp/ground_truth_scores.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
