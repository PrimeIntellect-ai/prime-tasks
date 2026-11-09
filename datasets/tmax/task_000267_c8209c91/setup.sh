#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_service.py
import json
import math
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

class SensorHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        if parsed_path.path == '/data':
            qs = parse_qs(parsed_path.query)
            if 'x' in qs:
                try:
                    x = float(qs['x'][0])
                    # Synthetic data: A sharp peak at x=0.55
                    base_signal = math.exp(-200 * (x - 0.55)**2)
                    # 5 frequencies
                    freqs = [1, 2, 3, 4, 5]
                    readings = [base_signal * math.cos(f * x) + 0.1 * math.sin(f * 10 * x) for f in freqs]

                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps(readings).encode())
                    return
                except ValueError:
                    pass
        self.send_response(400)
        self.end_headers()

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8000)
    httpd = HTTPServer(server_address, SensorHandler)
    httpd.serve_forever()
EOF

    chmod +x /home/user/sensor_service.py

    cat << 'EOF' > /home/user/verify.py
import numpy as np
import urllib.request
import json
import math
import sys

def get_data(x):
    base_signal = math.exp(-200 * (x - 0.55)**2)
    freqs = [1, 2, 3, 4, 5]
    return [base_signal * math.cos(f * x) + 0.1 * math.sin(f * 10 * x) for f in freqs]

# Phase A
x_init = np.linspace(0, 1.0, 11)
M = np.array([get_data(x) for x in x_init])
U, S, Vt = np.linalg.svd(M, full_matrices=False)
S_truncated = np.zeros_like(S)
S_truncated[:2] = S[:2]
M_denoised_init = U @ np.diag(S_truncated) @ Vt

def project(v):
    # Projection of a new vector v onto the top 2 right singular vectors
    v_proj = np.zeros_like(v)
    for i in range(2):
         v_proj += np.dot(v, Vt[i]) * Vt[i]
    return v_proj

def calc_S(v):
    return np.sum(v**2)

points = list(x_init)
S_vals = [calc_S(M_denoised_init[i]) for i in range(len(x_init))]

# Phase B
while True:
    refined = False
    new_points = []
    new_S_vals = []
    for i in range(len(points) - 1):
        new_points.append(points[i])
        new_S_vals.append(S_vals[i])

        if abs(S_vals[i] - S_vals[i+1]) > 0.5:
            x_mid = (points[i] + points[i+1]) / 2.0
            v_raw = np.array(get_data(x_mid))
            v_proj = project(v_raw)
            s_mid = calc_S(v_proj)
            new_points.append(x_mid)
            new_S_vals.append(s_mid)
            refined = True

    new_points.append(points[-1])
    new_S_vals.append(S_vals[-1])

    points = new_points
    S_vals = new_S_vals

    if not refined:
        break

# Phase C
points = np.array(points)
S_vals = np.array(S_vals)

# Trapezoidal rule for area A
A = np.trapz(S_vals, points)
P = S_vals / A

# CDF
C = np.zeros_like(P)
for i in range(1, len(points)):
    C[i] = C[i-1] + 0.5 * (points[i] - points[i-1]) * (P[i] + P[i-1])

# Wasserstein distance
W = 0.0
for i in range(len(points) - 1):
    w_i = 0.5 * (points[i+1] - points[i]) * (abs(C[i] - points[i]) + abs(C[i+1] - points[i+1]))
    W += w_i

expected_result = round(W, 6)

try:
    with open('/home/user/result.txt', 'r') as f:
        val = float(f.read().strip())
    if abs(val - expected_result) < 1e-5:
        print("PASS")
        sys.exit(0)
    else:
        print(f"FAIL: Expected {expected_result}, got {val}")
        sys.exit(1)
except Exception as e:
    print(f"FAIL: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
