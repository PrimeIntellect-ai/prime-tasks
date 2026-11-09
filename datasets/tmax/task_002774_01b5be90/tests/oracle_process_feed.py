import sys
import re
import pandas as pd
import numpy as np

def main():
    input_text = sys.stdin.read()
    pattern = re.compile(r'\[(\d+)\] METRIC_VAL:\s*([+-]?\d*\.?\d+)')
    matches = pattern.findall(input_text)

    if not matches:
        print("timestamp,value")
        return

    data = [(int(t), float(v)) for t, v in matches]
    df = pd.DataFrame(data, columns=['timestamp', 'value'])
    df = df.sort_values('timestamp').drop_duplicates('timestamp')

    min_t = df['timestamp'].min()
    max_t = df['timestamp'].max()

    full_range = pd.DataFrame({'timestamp': range(min_t, max_t + 1)})
    df = pd.merge(full_range, df, on='timestamp', how='left')
    df['value'] = df['value'].interpolate(method='linear')

    df['value'] = df['value'].round(2)

    df.to_csv(sys.stdout, index=False)

if __name__ == '__main__':
    main()
