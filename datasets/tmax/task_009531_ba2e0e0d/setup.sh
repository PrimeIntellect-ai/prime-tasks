#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/analyze_signal.py
import numpy as np

def generate_signal():
    N = 10000000
    # 10 seconds of data, sampled at 1 MHz
    t = np.linspace(0, 10, N, endpoint=False, dtype=np.float32)

    np.random.seed(42)
    # Signal with specific frequencies
    y = 1.5 * np.sin(2 * np.pi * 50 * t) + 0.5 * np.sin(2 * np.pi * 120 * t)
    y += np.random.normal(0, 0.1, N).astype(np.float32)
    return y

def main():
    y = generate_signal()
    N = len(y)

    # Time domain energy (flawed summation)
    energy_time = np.sum(y**2)

    # Frequency domain energy (flawed summation)
    Y = np.fft.fft(y)
    energy_freq = np.sum(np.abs(Y)**2) / N

    diff = abs(energy_time - energy_freq)

    with open("/home/user/energy_diff.txt", "w") as f:
        f.write(f"{diff}\n")

    print(f"Time Energy: {energy_time}")
    print(f"Freq Energy: {energy_freq}")
    print(f"Difference: {diff}")

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
