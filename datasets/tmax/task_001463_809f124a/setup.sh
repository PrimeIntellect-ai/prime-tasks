#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import pandas as pd
import json

# Ground truth parameters
np.random.seed(42)
t = np.arange(0, 101, 1)
k1_true = 0.12
k2_true = 0.04
A0 = 5.0

# Generate concentrations
A = A0 * np.exp(-k1_true * t)
B = A0 * (k1_true / (k2_true - k1_true)) * (np.exp(-k1_true * t) - np.exp(-k2_true * t))
C = A0 * (1 - (k2_true * np.exp(-k1_true * t) - k1_true * np.exp(-k2_true * t)) / (k2_true - k1_true))
C_mat = np.column_stack((A, B, C))

# Generate spectra (Gaussians)
wv = np.arange(400, 701, 1)
def gaussian(x, mu, sig):
    return np.exp(-np.power(x - mu, 2.) / (2 * np.power(sig, 2.)))

S_A = gaussian(wv, 450, 20)
S_B = gaussian(wv, 550, 30)
S_C = gaussian(wv, 650, 25)
S_mat = np.row_stack((S_A, S_B, S_C))

# Mix and add noise
M_mat = C_mat @ S_mat
noise = np.random.normal(0, 0.02, M_mat.shape)
M_mat_noisy = M_mat + noise

# Save pure spectra
df_S = pd.DataFrame(S_mat, columns=[f"wv_{w}" for w in wv])
df_S.insert(0, 'species', ['A', 'B', 'C'])
df_S.to_csv('/home/user/pure_spectra.csv', index=False)

# Save raw spectra
df_M = pd.DataFrame(M_mat_noisy, columns=[f"wv_{w}" for w in wv])
df_M.insert(0, 'time', t)
df_M.to_csv('/home/user/spectra_raw.csv', index=False)

# Ground truth calculation for verification
U, s, Vt = np.linalg.svd(M_mat_noisy, full_matrices=False)
svd_top3 = s[:3]
with open('/tmp/truth_svd.txt', 'w') as f:
    f.write(f"{svd_top3[0]:.4f},{svd_top3[1]:.4f},{svd_top3[2]:.4f}")

# Unmix
C_extracted, _, _, _ = np.linalg.lstsq(S_mat.T, M_mat_noisy.T, rcond=None)
C_extracted = C_extracted.T
A_ex = C_extracted[:, 0]
B_ex = C_extracted[:, 1]
C_ex = C_extracted[:, 2]

A0_ex = A_ex[0] + B_ex[0] + C_ex[0]

from scipy.optimize import minimize

def objective(k):
    k1, k2 = k
    if k1 == k2:
        return 1e10
    A_pred = A0_ex * np.exp(-k1 * t)
    B_pred = A0_ex * (k1 / (k2 - k1)) * (np.exp(-k1 * t) - np.exp(-k2 * t))
    C_pred = A0_ex * (1 - (k2 * np.exp(-k1 * t) - k1 * np.exp(-k2 * t)) / (k2 - k1))

    err_A = np.sum((A_pred - A_ex)**2)
    err_B = np.sum((B_pred - B_ex)**2)
    err_C = np.sum((C_pred - C_ex)**2)
    return err_A + err_B + err_C

res = minimize(objective, [0.1, 0.1], method='Nelder-Mead')
with open('/tmp/truth_kinetics.json', 'w') as f:
    json.dump({"k1": round(res.x[0], 4), "k2": round(res.x[1], 4)}, f)
EOF

    python3 /tmp/setup_data.py
    chmod -R 777 /home/user
