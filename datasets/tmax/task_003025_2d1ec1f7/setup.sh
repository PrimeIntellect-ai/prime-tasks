#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np
import pandas as pd

# Create directories
os.makedirs("/home/user/spectroscopy", exist_ok=True)

# Generate Wavelengths
x = np.linspace(0, 100, 101)

# Generate Reference Spectra (Gaussian peaks)
def gaussian(x, mu, sig):
    return np.exp(-np.power(x - mu, 2.) / (2 * np.power(sig, 2.)))

# Comp1 and Comp2 are highly collinear (near-singular)
c1 = gaussian(x, 40, 5)
c2 = gaussian(x, 41, 5) # very close to c1
c3 = gaussian(x, 70, 10)
c4 = gaussian(x, 85, 3)

df_refs = pd.DataFrame({
    'Wavelength': x,
    'Comp1': c1,
    'Comp2': c2,
    'Comp3': c3,
    'Comp4': c4
})
df_refs.to_csv("/home/user/spectroscopy/refs.csv", index=False)

# Generate Mixture Spectrum with a baseline
true_beta = np.array([1.5, 0.8, 2.0, 0.0])
pure_mixture = 1.5*c1 + 0.8*c2 + 2.0*c3 + 0.0*c4

# Baseline: 0.002*x^2 - 0.1*x + 5.0
baseline = 0.002 * x**2 - 0.1 * x + 5.0
intensity = pure_mixture + baseline

df_mix = pd.DataFrame({
    'Wavelength': x,
    'Intensity': intensity
})
df_mix.to_csv("/home/user/spectroscopy/mixture.csv", index=False)

# Historical bounds
bounds = {
    "Comp1": [1.0, 2.0],
    "Comp2": [0.0, 1.0],
    "Comp3": [1.5, 2.5],
    "Comp4": [-0.5, 0.5]
}
with open("/home/user/spectroscopy/historical_bounds.json", "w") as f:
    json.dump(bounds, f, indent=4)

# --- Compute Expected Truth ---
# 1. Baseline correction
poly_coeffs = np.polyfit(x, intensity, 2)
fitted_baseline = np.polyval(poly_coeffs, x)
corrected_intensity = intensity - fitted_baseline

# 2. SVD
X = df_refs[['Comp1', 'Comp2', 'Comp3', 'Comp4']].values
U, S, Vt = np.linalg.svd(X, full_matrices=False)

# 3. Truncated Pseudoinverse
threshold = 0.05
S_inv = np.zeros_like(S)
for i in range(len(S)):
    if S[i] >= threshold:
        S_inv[i] = 1.0 / S[i]
    else:
        S_inv[i] = 0.0

X_pinv = Vt.T @ np.diag(S_inv) @ U.T
beta = X_pinv @ corrected_intensity

# Generate expected report text
expected_report = f"Singular values: {S[0]:.4f}, {S[1]:.4f}, {S[2]:.4f}, {S[3]:.4f}\n"
expected_report += f"Comp1: {beta[0]:.4f} ({'IN_BOUNDS' if bounds['Comp1'][0] <= beta[0] <= bounds['Comp1'][1] else 'OUT_OF_BOUNDS'})\n"
expected_report += f"Comp2: {beta[1]:.4f} ({'IN_BOUNDS' if bounds['Comp2'][0] <= beta[1] <= bounds['Comp2'][1] else 'OUT_OF_BOUNDS'})\n"
expected_report += f"Comp3: {beta[2]:.4f} ({'IN_BOUNDS' if bounds['Comp3'][0] <= beta[2] <= bounds['Comp3'][1] else 'OUT_OF_BOUNDS'})\n"
expected_report += f"Comp4: {beta[3]:.4f} ({'IN_BOUNDS' if bounds['Comp4'][0] <= beta[3] <= bounds['Comp4'][1] else 'OUT_OF_BOUNDS'})"

with open("/home/user/spectroscopy/expected_report.txt", "w") as f:
    f.write(expected_report)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
