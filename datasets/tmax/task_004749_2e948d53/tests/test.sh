#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
import h5py
from scipy.io import wavfile
from scipy.signal import welch
from scipy.optimize import curve_fit

def model_func(f, A, B, C):
    return A * np.exp(-B * f) + C

def compute_reference_solution(audio_path):
    fs, data = wavfile.read(audio_path)

    # Welch's method
    f, Pxx = welch(data, fs=fs, window='hann', nperseg=1024, noverlap=512)

    # Curve fitting
    # Provide reasonable initial guesses to avoid issues
    p0 = [np.max(Pxx), 1e-3, np.min(Pxx)]
    popt, _ = curve_fit(model_func, f, Pxx, p0=p0, maxfev=10000)

    # KL Divergence
    P_fit = model_func(f, *popt)

    # Normalize
    P_emp_norm = Pxx / np.sum(Pxx)
    P_fit_norm = P_fit / np.sum(P_fit)

    # Add epsilon
    eps = 1e-10
    P_emp_eps = P_emp_norm + eps
    P_fit_eps = P_fit_norm + eps

    # Compute KL
    kl_div = np.sum(P_emp_eps * np.log(P_emp_eps / P_fit_eps))

    return popt, kl_div

def test_analysis_results():
    audio_path = "/app/turbine_audio.wav"
    student_h5_path = "/home/user/analysis_results.h5"

    assert os.path.exists(student_h5_path), f"Student output file not found at {student_h5_path}"

    # Compute reference solution
    ref_params, ref_kl = compute_reference_solution(audio_path)

    try:
        with h5py.File(student_h5_path, 'r') as f_agent:
            assert 'model_fit/parameters' in f_agent, "Missing dataset 'model_fit/parameters' in HDF5 file."
            assert 'model_fit/kl_divergence' in f_agent, "Missing dataset 'model_fit/kl_divergence' in HDF5 file."

            agent_params = f_agent['model_fit/parameters'][:]
            agent_kl = f_agent['model_fit/kl_divergence'][()]
    except Exception as e:
        pytest.fail(f"Failed to read student HDF5 file: {e}")

    mse_params = np.mean((agent_params - ref_params)**2)
    diff_kl = np.abs(agent_kl - ref_kl)

    assert mse_params < 1e-4, f"Parameter MSE {mse_params} exceeds threshold 1e-4. Expected roughly {ref_params}, got {agent_params}."
    assert diff_kl < 1e-3, f"KL divergence absolute difference {diff_kl} exceeds threshold 1e-3. Expected roughly {ref_kl}, got {agent_kl}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
