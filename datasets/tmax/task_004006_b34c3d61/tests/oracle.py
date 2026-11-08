#!/usr/bin/env python3
import sys
import json
import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression

def main():
    try:
        data = json.load(sys.stdin)
        if not data:
            print(json.dumps({"error": "insufficient data"}))
            return

        df = pd.DataFrame(data)
        if df.empty or not all(k in df.columns for k in ['A', 'B', 'C']):
            print(json.dumps({"error": "insufficient data"}))
            return

        df.loc[df['A'] < 0, 'A'] = np.nan
        df['A'] = df['A'].ffill()
        df = df.dropna()

        if len(df) < 3 or df['A'].var() == 0 or df['B'].var() == 0:
            print(json.dumps({"error": "insufficient data"}))
            return

        corr = df['A'].corr(df['B'])
        X = df[['A', 'B']]
        y = df['C']

        model = LinearRegression().fit(X, y)

        res = {
            "correlation": round(float(corr), 4),
            "coefficients": [
                round(float(model.intercept_), 4),
                round(float(model.coef_[0]), 4),
                round(float(model.coef_[1]), 4)
            ]
        }
        print(json.dumps(res))
    except Exception as e:
        print(json.dumps({"error": "insufficient data"}))

if __name__ == "__main__":
    main()
