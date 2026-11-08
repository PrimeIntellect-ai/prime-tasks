#!/usr/bin/env python3
import sys
import pandas as pd
import numpy as np

def main():
    df = pd.read_csv(sys.stdin)
    if 'value' in df.columns:
        mean_val = np.floor(df['value'].mean())
        df['value'] = df['value'].fillna(mean_val)
        df['value'] = df['value'].astype(int)
        df['value'] = df['value'] - 17
    df.to_csv(sys.stdout, index=False)

if __name__ == '__main__':
    main()
