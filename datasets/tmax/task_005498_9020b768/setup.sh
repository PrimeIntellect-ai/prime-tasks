#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/model_fit.py
import numpy as np
import scipy.integrate as integrate
import sys

def integrand(x, a):
    return a * np.sin(x) * np.exp(-x**2)

def integrate_numeric(a):
    result, _ = integrate.quad(integrand, 0, 2, args=(a,))
    return result

def integrate_mc(a, n_samples=1000000, seed=42):
    np.random.seed(seed)
    samples = np.random.uniform(0, 2, n_samples)
    # BUG: Missing the volume multiplier for MC integration. 
    # Should be: return 2.0 * np.mean(integrand(samples, a))
    return np.mean(integrand(samples, a))

def test_regression():
    a_test = 2.0
    val_num = integrate_numeric(a_test)
    val_mc = integrate_mc(a_test)
    if abs(val_num - val_mc) > 1e-2:
        print(f"Regression failed! Numeric: {val_num:.5f}, MC: {val_mc:.5f}")
        sys.exit(1)
    print("Regression passed.")

def fit_model(target=1.5):
    # The integral is linear with respect to 'a'
    # target = a * integral(sin(x)*exp(-x^2))
    base_integral = integrate_mc(1.0)
    a_fit = target / base_integral
    return a_fit

if __name__ == "__main__":
    test_regression()
    a_fitted = fit_model(1.5)
    with open("/home/user/fit_result.txt", "w") as f:
        f.write(f"{a_fitted:.4f}\n")
EOF

    chmod -R 777 /home/user
