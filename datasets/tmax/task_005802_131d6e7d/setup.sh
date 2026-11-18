#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/metadata.csv
model_id,architecture
101,transformer
102,cnn
103,rnn
104,transformer
105,cnn
EOF

    cat << 'EOF' > /home/user/benchmarks.csv
id ,inference_ms
101 ,45.2
102 ,12.5
103 ,25.1
104 ,48.8
105 ,14.3
EOF

    cat << 'EOF' > /home/user/prepare_data.py
import pandas as pd
import matplotlib.pyplot as plt

# Load data
meta = pd.read_csv('/home/user/metadata.csv')
benchmarks = pd.read_csv('/home/user/benchmarks.csv')

# Join data
# The developer didn't notice the trailing space in the benchmarks.csv 'id ' column
try:
    merged = pd.merge(meta, benchmarks, left_on='model_id', right_on='id')
except KeyError:
    # Fallback that creates an empty dataframe if join fails
    merged = pd.DataFrame(columns=['model_id', 'architecture', 'id', 'inference_ms'])

# Aggregate
summary = merged.groupby('architecture')['inference_ms'].mean().reset_index()

# Save summary
summary.to_csv('/home/user/summary.csv', index=False)

# Plot
plt.figure()
plt.bar(summary['architecture'] if not summary.empty else [], summary['inference_ms'] if not summary.empty else [])
plt.title('Average Inference Time by Architecture')
plt.savefig('/home/user/benchmark_plot.png')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
