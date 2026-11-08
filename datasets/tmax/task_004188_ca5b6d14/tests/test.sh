#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import struct
import pytest

def simulate_heat_pure_python():
    alpha = 0.01
    L = 1.0
    T = 0.5
    Nx = 50
    dt = 0.005
    dx = L / (Nx - 1)

    x = [i * dx for i in range(Nx)]
    u = [math.sin(math.pi * xi) for xi in x]

    steps = int(round(T / dt))
    for _ in range(steps):
        u_new = list(u)
        for i in range(1, Nx - 1):
            u_new[i] = u[i] + alpha * dt / (dx**2) * (u[i+1] - 2*u[i] + u[i-1])
        u = u_new
    return x, u

def read_obs_data():
    csv_path = '/home/user/obs_data.csv'
    if not os.path.exists(csv_path):
        pytest.fail(f"Missing observational data file: {csv_path}")

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        data = []
        for row in reader:
            data.append((float(row['raw_x']), float(row['raw_temp'])))
        data.sort(key=lambda item: item[0])
        return [item[1] for item in data]

def calc_mse(u_sim, u_obs):
    return sum((s - o)**2 for s, o in zip(u_sim, u_obs)) / len(u_sim)

def polyfit2(x, y):
    N = len(x)
    sx = sum(x)
    sx2 = sum(xi**2 for xi in x)
    sx3 = sum(xi**3 for xi in x)
    sx4 = sum(xi**4 for xi in x)

    sy = sum(y)
    sxy = sum(xi*yi for xi, yi in zip(x, y))
    sx2y = sum(xi**2 * yi for xi, yi in zip(x, y))

    def det3(m):
        return (m[0][0]*(m[1][1]*m[2][2] - m[1][2]*m[2][1]) -
                m[0][1]*(m[1][0]*m[2][2] - m[1][2]*m[2][0]) +
                m[0][2]*(m[1][0]*m[2][1] - m[1][1]*m[2][0]))

    M = [[sx4, sx3, sx2],
         [sx3, sx2, sx],
         [sx2, sx, N]]

    D = det3(M)

    Ma = [[sx2y, sx3, sx2],
          [sxy, sx2, sx],
          [sy, sx, N]]

    Mb = [[sx4, sx2y, sx2],
          [sx3, sxy, sx],
          [sx2, sy, N]]

    Mc = [[sx4, sx3, sx2y],
          [sx3, sx2, sxy],
          [sx2, sx, sy]]

    a = det3(Ma) / D
    b = det3(Mb) / D
    c = det3(Mc) / D

    return [a, b, c]

def read_npy_1d(path):
    with open(path, 'rb') as f:
        magic = f.read(6)
        if magic != b'\x93NUMPY':
            pytest.fail(f"File {path} is not a valid .npy file")
        f.read(2) # version
        header_len_data = f.read(2)
        header_len = struct.unpack('<H', header_len_data)[0]
        header = f.read(header_len).decode('ascii', errors='ignore')

        if "'descr': '<f8'" in header:
            fmt = 'd'
            b = 8
        elif "'descr': '<f4'" in header:
            fmt = 'f'
            b = 4
        else:
            fmt = 'd'
            b = 8

        data = f.read()
        num_elements = len(data) // b
        return struct.unpack(f'<{num_elements}{fmt}', data)

def test_simulated_profile():
    npy_path = '/home/user/simulated_profile.npy'
    assert os.path.exists(npy_path), f"Simulated profile not found at {npy_path}"

    saved_u = read_npy_1d(npy_path)
    assert len(saved_u) == 50, f"Expected 50 points in simulated profile, got {len(saved_u)}"

    _, expected_u = simulate_heat_pure_python()

    for s, e in zip(saved_u, expected_u):
        assert abs(s - e) < 1e-4, f"Simulated profile values do not match expected. Expected ~{e}, got {s}"

def test_results_json():
    json_path = '/home/user/results.json'
    assert os.path.exists(json_path), f"Results JSON not found at {json_path}"

    with open(json_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON")

    assert "poly_coeffs" in results, "Key 'poly_coeffs' missing from results.json"
    assert "mse" in results, "Key 'mse' missing from results.json"

    poly_coeffs = results["poly_coeffs"]
    mse = results["mse"]

    assert isinstance(poly_coeffs, list) and len(poly_coeffs) == 3, "'poly_coeffs' must be a list of 3 floats"
    assert isinstance(mse, (int, float)), "'mse' must be a float"

    x, expected_u = simulate_heat_pure_python()
    u_obs = read_obs_data()

    expected_mse = calc_mse(expected_u, u_obs)
    expected_coeffs = polyfit2(x, expected_u)

    assert abs(mse - expected_mse) < 1e-4, f"MSE is incorrect. Expected ~{expected_mse}, got {mse}"

    for c_stu, c_exp in zip(poly_coeffs, expected_coeffs):
        assert abs(c_stu - c_exp) < 1e-4, f"Polynomial coefficients are incorrect. Expected {expected_coeffs}, got {poly_coeffs}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
