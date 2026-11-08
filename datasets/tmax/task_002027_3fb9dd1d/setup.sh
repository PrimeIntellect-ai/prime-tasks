#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest pandas cloudpickle

    mkdir -p /app
    cd /app
    wget https://files.pythonhosted.org/packages/source/j/joblib/joblib-1.3.2.tar.gz
    tar -xzf joblib-1.3.2.tar.gz
    rm joblib-1.3.2.tar.gz

    # Introduce the deliberate typo perturbation
    sed -i "s/setup(/setup(install_requires=['cloudpcikle'], /g" /app/joblib-1.3.2/setup.py

    # Create the oracle reference script
    cat << 'EOF' > /app/oracle_analyze.py
import sys
import pandas as pd
from joblib import Parallel, delayed

def process_group(df):
    df = df.sort_values('timestamp')
    df['rolling_avg'] = df.groupby('variable')['value'].transform(lambda x: x.rolling(3).mean())
    df['rolling_avg'] = df['rolling_avg'].apply(lambda x: f"{x:.2f}" if pd.notnull(x) else "")
    return df

if __name__ == "__main__":
    df = pd.read_csv(sys.stdin)
    if df.empty:
        print("timestamp,sensor_id,variable,value,rolling_avg")
        sys.exit(0)

    long_df = df.melt(id_vars=['timestamp', 'sensor_id'], value_vars=['metric_a', 'metric_b', 'metric_c'], var_name='variable')

    # Process parallel
    grouped = [group for _, group in long_df.groupby('sensor_id')]
    processed_groups = Parallel(n_jobs=-1)(delayed(process_group)(g) for g in grouped)

    final_df = pd.concat(processed_groups)
    final_df = final_df.sort_values(['sensor_id', 'variable', 'timestamp'])
    final_df.to_csv(sys.stdout, index=False)
EOF
    chmod +x /app/oracle_analyze.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
