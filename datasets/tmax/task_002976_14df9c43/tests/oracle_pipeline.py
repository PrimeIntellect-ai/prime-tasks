#!/usr/bin/env python3
import sys
import numpy as np

def process():
    lines = sys.stdin.read().strip().split('\n')
    if not lines or lines == ['']: return

    data = []
    for line in lines:
        row = [np.nan if x == '' else float(x) for x in line.split(',')]
        data.append(row)

    arr = np.array(data, dtype=np.float64)

    # 1. Impute
    col_means = np.nanmean(arr, axis=0)
    inds = np.where(np.isnan(arr))
    arr[inds] = np.take(col_means, inds[1])

    # 2. Clip (Z = 2.5)
    Z = 2.5
    m2 = np.mean(arr, axis=0)
    s2 = np.std(arr, axis=0, ddof=1)
    lower = m2 - Z * s2
    upper = m2 + Z * s2
    arr = np.clip(arr, lower, upper)

    # 3. Standardize
    m3 = np.mean(arr, axis=0)
    s3 = np.std(arr, axis=0, ddof=1)
    arr = (arr - m3) / s3

    # 4. Covariance
    cov = np.cov(arr, rowvar=False, ddof=1)

    # 5. Output
    cov_rounded = np.round(cov, 4)
    for row in cov_rounded:
        print(','.join([f"{val:.4f}" for val in row]))

if __name__ == "__main__":
    process()
