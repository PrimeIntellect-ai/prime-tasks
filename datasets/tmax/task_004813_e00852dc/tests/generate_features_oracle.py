#!/usr/bin/env python3
import sys
import math

def init_chain(x):
    return x * 1.5 + 2.0

def stable_log_posterior(y):
    w1, mu1, var1 = 0.3, -5.0, 1.0
    w2, mu2, var2 = 0.7, 5.0, 1.0

    log_w1 = math.log(w1)
    log_w2 = math.log(w2)

    log_p1 = log_w1 - 0.5 * ((y - mu1)**2)
    log_p2 = log_w2 - 0.5 * ((y - mu2)**2)

    m = max(log_p1, log_p2)
    if math.isinf(m):
        return m
    return m + math.log(math.exp(log_p1 - m) + math.exp(log_p2 - m))

if __name__ == "__main__":
    x = float(sys.argv[1])
    y = init_chain(x)
    val = stable_log_posterior(y)
    print(f"{val:.6f}")
