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
