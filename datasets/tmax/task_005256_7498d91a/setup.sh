#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib

    useradd -m -s /bin/bash user || true

    # Run Python script to generate datasets and oracle
    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs("/home/user/data/clean", exist_ok=True)
os.makedirs("/home/user/data/evil", exist_ok=True)
os.makedirs("/app", exist_ok=True)

def generate_samples(n, is_clean=True, seed=None):
    if seed is not None:
        np.random.seed(seed)

    n1 = int(n * 0.6)
    n2 = n - n1

    if is_clean:
        s1 = np.random.normal(0, 1.0, n1)
        s2 = np.random.normal(4, 1.5, n2)
    else:
        s1 = np.random.normal(0.5, 1.2, n1)
        s2 = np.random.normal(3.5, 1.3, n2)

    samples = np.concatenate([s1, s2])
    np.random.shuffle(samples)
    return samples.astype(np.float64)

np.random.seed(42)
for i in range(50):
    clean_data = generate_samples(5000, is_clean=True)
    np.save(f"/home/user/data/clean/sample_{i:03d}.npy", clean_data)

    evil_data = generate_samples(5000, is_clean=False)
    np.save(f"/home/user/data/evil/sample_{i:03d}.npy", evil_data)

oracle_source = """
import sys
import numpy as np

def main():
    if len(sys.argv) != 4 or sys.argv[1] != '--generate':
        print("Usage: telemetry_oracle --generate <num> <out.npy>")
        sys.exit(1)

    n = int(sys.argv[2])
    out_file = sys.argv[3]

    # Generate clean reference distribution
    np.random.seed(1337)
    n1 = int(n * 0.6)
    n2 = n - n1
    s1 = np.random.normal(0, 1.0, n1)
    s2 = np.random.normal(4, 1.5, n2)

    samples = np.concatenate([s1, s2])
    np.random.shuffle(samples)
    np.save(out_file, samples.astype(np.float64))

if __name__ == '__main__':
    main()
"""

with open("/app/oracle.py", "w") as f:
    f.write(oracle_source)

wrapper = """#!/bin/bash
python3 /app/oracle.py "$@"
"""
with open("/app/telemetry_oracle", "w") as f:
    f.write(wrapper)
os.chmod("/app/telemetry_oracle", 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
