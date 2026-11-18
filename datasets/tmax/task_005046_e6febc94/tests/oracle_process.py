import sys
import math
import numpy as np
from scipy.stats import gaussian_kde

def main():
    line = sys.stdin.read().strip()
    if not line: return
    data = [float(x) for x in line.split(',')]

    kde = gaussian_kde(data)
    x_eval = np.linspace(-10.0, 10.0, 200)
    densities = kde(x_eval)
    A = np.max(densities)

    w0 = 2.5
    dt = 0.05

    y = 0.0
    v = 0.0
    y_list = []

    for i in range(200):
        t = i * dt
        y_new = y + dt * v
        v_new = v + dt * (A * math.sin(2.0 * t) - 0.1 * v - (w0**2) * y)
        y = y_new
        v = v_new
        y_list.append(y)

    fft_res = np.fft.fft(y_list)
    max_mag = np.max(np.abs(fft_res))
    print(f"{max_mag:.4f}")

if __name__ == "__main__":
    main()
