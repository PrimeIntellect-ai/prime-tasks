#!/usr/bin/env python3
import sys
import json
import math

def pearson(x, y):
    n = len(x)
    if n < 2: return 0.0
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y))
    var_x = sum((a - mean_x) ** 2 for a in x)
    var_y = sum((b - mean_y) ** 2 for b in y)
    if var_x == 0 or var_y == 0: return 0.0
    return num / math.sqrt(var_x * var_y)

def main():
    try:
        data = json.load(sys.stdin)
    except:
        print(json.dumps({"cleaned_data": [], "correlation": 0.0}))
        return

    cleaned = []
    valid_f1 = []
    valid_f2 = []

    for row in data:
        if not isinstance(row, dict) or "f1" not in row or "f2" not in row:
            continue

        v1 = row["f1"]
        v2 = row["f2"]

        if v1 is not None:
            v1 = max(-5.0, min(5.0, float(v1)))
            valid_f1.append(v1)
        else:
            v1 = sum(valid_f1) / len(valid_f1) if valid_f1 else 0.0

        if v2 is not None:
            v2 = max(-5.0, min(5.0, float(v2)))
            valid_f2.append(v2)
        else:
            v2 = sum(valid_f2) / len(valid_f2) if valid_f2 else 0.0

        cleaned.append({"f1": v1, "f2": v2})

    f1_arr = [r["f1"] for r in cleaned]
    f2_arr = [r["f2"] for r in cleaned]

    corr = pearson(f1_arr, f2_arr)

    print(json.dumps({"cleaned_data": cleaned, "correlation": round(corr, 4)}))

if __name__ == "__main__":
    main()
