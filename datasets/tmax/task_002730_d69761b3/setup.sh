#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas matplotlib scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_latency_data.csv
timestamp,server_group,latency_ms
2023-10-01T10:00:00Z,A,102.5
2023-10-01T10:01:00Z,B,115.2
2023-10-01T10:02:00Z,A,98.1
2023-10-01T10:03:00Z,B,110.8
2023-10-01T10:04:00Z,A,105.0
2023-10-01T10:05:00Z,B,118.5
2023-10-01T10:06:00Z,A,101.2
2023-10-01T10:07:00Z,B,112.4
2023-10-01T10:08:00Z,A,99.5
2023-10-01T10:09:00Z,B,114.1
EOF

    cat << 'EOF' > /home/user/analyze_and_plot.py
import pandas as pd
import matplotlib.pyplot as plt
from scipy import stats

def main():
    df = pd.read_csv('/home/user/raw_latency_data.csv')

    group_a = df[df['server_group'] == 'A']['latency_ms']
    group_b = df[df['server_group'] == 'B']['latency_ms']

    t_stat, p_val = stats.ttest_ind(group_a, group_b)

    # Needs to be output to /home/user/p_value.txt

    plt.boxplot([group_a, group_b], labels=['Group A', 'Group B'])
    plt.title('Server Latency by Group')
    plt.ylabel('Latency (ms)')

    # This causes issues in headless environment and prevents saving if blocking
    plt.show()
    plt.savefig('/home/user/latency_plot.png')

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
