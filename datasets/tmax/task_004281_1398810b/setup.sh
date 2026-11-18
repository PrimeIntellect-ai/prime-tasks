#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > setup.py
import struct

# Create data.bin
# Format: 4 byte magic "DATA", 4 byte little-endian int N (100), then N float64s
data = [float(i) for i in range(1, 101)] # Mean = 50.5
with open('data.bin', 'wb') as f:
    f.write(b"DATA")
    f.write(struct.pack("<I", len(data)))
    for val in data:
        f.write(struct.pack("<d", val))

# Create solver.py with bugs
code = """import struct

def read_data(filepath):
    with open(filepath, 'rb') as f:
        # BUG: incorrect offset and type
        f.seek(4)
        data = f.read()
    floats = []
    # BUG: assuming float32 and no N parameter
    for i in range(0, len(data), 4):
        if i+4 <= len(data):
            floats.append(struct.unpack('<f', data[i:i+4])[0])
    return floats

def compute_stats(data):
    if not data: return 0.0
    mean = sum(data) / len(data)
    return mean

def optimize(target_mean):
    # Find x such that x^2 - target_mean * x is minimized
    x = 0.0
    lr = 0.1
    for i in range(100):
        grad = 2 * x - target_mean
        # BUG: Gradient ascent instead of descent causes convergence failure
        x = x + lr * grad
    return x

if __name__ == '__main__':
    data = read_data('data.bin')
    mean = compute_stats(data)
    best_x = optimize(mean)
    with open('output.txt', 'w') as f:
        f.write(f"Mean: {mean:.4f}\\n")
        f.write(f"Opt: {best_x:.4f}\\n")
"""
with open('solver.py', 'w') as f:
    f.write(code)
EOF

    python3 setup.py
    rm setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
