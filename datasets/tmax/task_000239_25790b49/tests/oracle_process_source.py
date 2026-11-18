import sys
import requests
import numpy as np

def main():
    if len(sys.argv) < 2:
        return
    seq = sys.argv[1]

    resp = requests.get('http://localhost:5000/api/params')
    data = resp.json()
    alpha = data['alpha']
    N = data['N']

    arr = np.array([1.0 if c in 'CG' else 0.0 for c in seq])
    L = len(arr)

    if L < 3:
        mean_val = np.mean(arr)
        indices = [str(i) for i, val in enumerate(arr) if val > mean_val]
        print(",".join(indices))
        return

    for _ in range(N):
        new_arr = np.copy(arr)
        for i in range(1, L - 1):
            new_arr[i] = arr[i] + alpha * (arr[i+1] - 2*arr[i] + arr[i-1])
        new_arr[0] = 0.0
        new_arr[L-1] = 0.0
        arr = new_arr

    mean_val = np.mean(arr)
    indices = [str(i) for i, val in enumerate(arr) if val > mean_val]
    print(",".join(indices))

if __name__ == "__main__":
    main()
