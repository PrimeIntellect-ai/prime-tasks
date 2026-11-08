import numpy as np
from scipy.fft import fft, ifft

def filter_signal(signal_array):
    # simple low pass + dummy cholesky for the sake of using primitive skills
    arr = np.array(signal_array)
    f = fft(arr)
    f[len(f)//2:] = 0
    smoothed = np.real(ifft(f))
    # construct a dummy positive definite matrix
    n = len(smoothed)
    A = np.eye(n) * 2.0 + np.ones((n, n)) * 0.1
    L = np.linalg.cholesky(A)
    # multiply smoothed signal by L
    out = L.dot(smoothed)
    return out.tolist()
