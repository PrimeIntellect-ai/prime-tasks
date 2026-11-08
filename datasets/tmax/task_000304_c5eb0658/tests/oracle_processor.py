import sys
import json
import numpy as np

def run():
    input_data = json.load(sys.stdin)
    X = np.array(input_data['data'], dtype=float)
    X_mean = np.mean(X, axis=0)
    X_c = X - X_mean
    C = np.cov(X, rowvar=False, ddof=1)
    if C.ndim == 0:
        C = np.array([[C]])
    Y = np.dot(X_c, C)

    C_rounded = np.round(C, 4).tolist()
    Y_rounded = np.round(Y, 4).tolist()

    print(json.dumps({"covariance": C_rounded, "transformed": Y_rounded}))

if __name__ == '__main__':
    run()
