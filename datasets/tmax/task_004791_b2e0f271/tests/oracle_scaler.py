#!/usr/bin/env python3
import sys
import json
import math

def process():
    input_data = sys.stdin.read()
    if not input_data.strip():
        return

    try:
        X = json.loads(input_data)
    except:
        sys.exit(1)

    Y = []
    for i in range(len(X)):
        window = X[:i+1]
        mu = sum(window) / len(window)
        variance = sum((x - mu) ** 2 for x in window) / len(window)
        sigma = math.sqrt(variance)

        y_val = (X[i] - mu) / (sigma + 0.01)
        Y.append(round(y_val, 4))

    print(json.dumps(Y))

if __name__ == "__main__":
    process()
