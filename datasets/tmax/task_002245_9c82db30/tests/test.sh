#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pandas as pd
from sklearn.metrics import mean_squared_error

def test_region_traffic_mse():
    output_csv = '/home/user/region_traffic.csv'
    assert os.path.isfile(output_csv), f"Output file {output_csv} does not exist."

    # 1. Recreate Ground Truth
    cmd = "ffprobe -show_frames -select_streams v:0 -of csv=p=0 -show_entries frame=pkt_size /app/traffic.mp4 | grep -v '^$' > /tmp/sizes.csv"
    subprocess.run(cmd, shell=True, check=True)

    sizes = pd.read_csv('/tmp/sizes.csv', header=None, names=['pkt_size'])
    topology = pd.read_csv('/app/topology.csv')

    # Map frame to node
    sizes['node_id'] = sizes.index % 500
    base_traffic = sizes.groupby('node_id')['pkt_size'].sum().reset_index()

    traffic_dict = {row['node_id']: row['pkt_size'] for _, row in base_traffic.iterrows()}
    for i in range(500):
        if i not in traffic_dict:
            traffic_dict[i] = 0

    # Compute recursive sizes (process bottom up)
    total_traffic = traffic_dict.copy()
    parent_map = {row['node_id']: row['parent_id'] for _, row in topology.iterrows()}

    for i in range(499, -1, -1):
        p = parent_map[i]
        if not pd.isna(p):
            total_traffic[int(p)] += total_traffic[i]

    # Aggregate top level by region
    roots = topology[topology['parent_id'].isna()].copy()
    roots['total'] = roots['node_id'].map(total_traffic)
    gt_region = roots.groupby('region')['total'].sum().reset_index().sort_values('region')

    # 2. Read agent's output
    try:
        agent_res = pd.read_csv(output_csv, header=None, names=['region', 'total'])
        # Handle potential header included by the agent
        if str(agent_res.iloc[0]['region']).lower() == 'region':
            agent_res = agent_res.iloc[1:]
            agent_res['total'] = pd.to_numeric(agent_res['total'])
    except Exception as e:
        assert False, f"Failed to parse {output_csv}: {e}"

    agent_res = agent_res.sort_values('region')

    # 3. Merge and compare
    merged = pd.merge(gt_region, agent_res, on='region', how='left').fillna(0)
    mse = mean_squared_error(merged['total_x'], merged['total_y'])

    assert mse < 1.0, f"MSE is {mse:.4f}, which is not strictly less than 1.0. Threshold: MSE < 1.0"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
