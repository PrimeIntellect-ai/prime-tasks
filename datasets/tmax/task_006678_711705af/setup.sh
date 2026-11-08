#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs("/home/user", exist_ok=True)
csv_path = "/home/user/sensor_data.csv"

x_vals = list(range(100))
y_vals = []
noise_state = 123
for x in x_vals:
    noise_state = (1103515245 * noise_state + 12345) % 2147483648
    noise = ((noise_state % 1000) / 1000.0 - 0.5) * 10.0
    y = 1.7 * x + 5.0 + noise
    y_vals.append(y)

with open(csv_path, "w") as f:
    f.write("x,y\n")
    for x, y in zip(x_vals, y_vals):
        f.write(f"{x},{y:.4f}\n")

state = 42
def get_random_index(num_points=100):
    global state
    state = (1103515245 * state + 12345) % 2147483648
    return state % num_points

slopes = []
for _ in range(10000):
    samp_x = []
    samp_y = []
    for _ in range(100):
        idx = get_random_index(100)
        samp_x.append(x_vals[idx])
        samp_y.append(y_vals[idx])

    n = 100
    sum_x = sum(samp_x)
    sum_y = sum(samp_y)
    sum_xy = sum(x*y for x, y in zip(samp_x, samp_y))
    sum_xx = sum(x*x for x in samp_x)

    denominator = n * sum_xx - sum_x**2
    if denominator == 0:
        slope = 0
    else:
        slope = (n * sum_xy - sum_x * sum_y) / denominator
    slopes.append(slope)

slopes.sort()
lower_bound = slopes[249]
upper_bound = slopes[9749]

expected_output = f"Slope CI: [{lower_bound:.4f}, {upper_bound:.4f}]"

with open("/tmp/expected_ci.txt", "w") as f:
    f.write(expected_output + "\n")
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
