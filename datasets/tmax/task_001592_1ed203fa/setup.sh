#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev espeak
    pip3 install pytest pandas

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/network_log.wav "Node Alpha connected to Node Beta with latency 45 milliseconds. Node Beta connected to Node Gamma with latency 12 milliseconds. Node Alpha connected to Node Beta with latency 41 milliseconds. Node Gamma connected to Node Delta with latency 88 milliseconds."

    # Create reference_graph.csv
    cat << 'EOF' > /app/reference_graph.csv
source,target,avg_latency
Alpha,Beta,43
Beta,Gamma,12
Gamma,Delta,88
EOF

    # Create verify_mse.py
    cat << 'EOF' > /app/verify_mse.py
import pandas as pd
import sys

def calculate_mse(agent_file, reference_file):
    try:
        agent_df = pd.read_csv(agent_file)
        ref_df = pd.read_csv(reference_file)

        # Merge on source and target
        merged = pd.merge(ref_df, agent_df, on=['source', 'target'], suffixes=('_ref', '_agent'))

        if len(merged) == 0:
            print("MSE: 9999.0")
            return

        mse = ((merged['avg_latency_ref'] - merged['avg_latency_agent']) ** 2).mean()
        print(f"MSE: {mse}")

        if mse <= 5.0:
            sys.exit(0)
        else:
            sys.exit(1)

    except Exception as e:
        print(f"MSE: 9999.0")
        sys.exit(1)

if __name__ == "__main__":
    calculate_mse("/home/user/graph_export.csv", "/app/reference_graph.csv")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
