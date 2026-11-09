#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
pip3 install pytest pandas numpy scikit-learn

mkdir -p /app

cat << 'EOF' > /app/oracle.py
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
EOF

chmod +x /app/oracle.py

espeak -w /app/requirements.wav "Write a Python script that reads a JSON array of objects from stdin. Each object has integer keys A, B, and C. Step one: Convert this to a pandas DataFrame. Step two: Any value in column A that is negative must be replaced with NaN. This will silently convert column A to floats. Step three: Forward-fill the NaNs in column A. If the first value is NaN, leave it as NaN. Step four: Drop any rows that still contain any NaN values. Step five: Compute the Pearson correlation coefficient between A and B. Step six: Fit a multiple linear regression model predicting C using A and B as predictors. Include an intercept. Output a JSON object with two keys: 'correlation' containing the correlation float, and 'coefficients' containing a list of floats: the intercept, the A coefficient, and the B coefficient. Round all output numbers to 4 decimal places. If the remaining dataframe has fewer than 3 rows, or if the variance of A or B is zero, output the JSON object {\"error\": \"insufficient data\"}."

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
