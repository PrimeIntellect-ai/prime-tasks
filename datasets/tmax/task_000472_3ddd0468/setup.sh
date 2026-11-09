#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    mkdir -p /home/user/sim_project/logs
    mkdir -p /home/user/sim_project/data
    mkdir -p /home/user/sim_project/states

    cat << 'EOF' > /home/user/sim_project/utils.py
import math

def compute_weights(values):
    """
    Computes the softmax probabilities of the input values.
    """
    # BUG: Numerical instability. Will overflow for large values.
    exps = [math.exp(v) for v in values]
    sum_exps = sum(exps)
    return [e / sum_exps for e in exps]
EOF

    cat << 'EOF' > /home/user/sim_project/main.py
import os
import glob
import logging
from concurrent.futures import ProcessPoolExecutor, as_completed
from utils import compute_weights

def process_file(filepath):
    pid = os.getpid()
    log_file = f"/home/user/sim_project/logs/worker_{pid}.log"
    logging.basicConfig(filename=log_file, level=logging.INFO, format='%(asctime)s - %(message)s')

    filename = os.path.basename(filepath)
    try:
        with open(filepath, 'r') as f:
            data = [float(x.strip()) for x in f.readlines()]

        weights = compute_weights(data)
        return sum(weights)
    except OverflowError:
        logging.error(f"OverflowError encountered while processing {filename}")
        # BUG: File descriptor leak. Opens file to dump state but never closes it.
        # It loops to try and save intermediate state parts, leaking an FD each time.
        for i in range(10):
            f = open(f"/home/user/sim_project/states/error_state_{pid}_{i}.dmp", 'w')
            f.write("ERROR STATE DUMP")
            # Missing f.close()

        # Trigger continuous failure loop simulating retry mechanics
        raise

def main():
    files = glob.glob("/home/user/sim_project/data/input_*.txt")
    total_aggregate = 0.0

    # Intentionally restrict the max open files for this process to simulate the crash faster
    import resource
    resource.setrlimit(resource.RLIMIT_NOFILE, (100, 100))

    with ProcessPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(process_file, f): f for f in files}
        for future in as_completed(futures):
            try:
                res = future.result()
                total_aggregate += res
            except Exception as e:
                # Retry loop causing FD exhaustion
                pass

    with open("/home/user/sim_project/aggregate_result.txt", 'w') as f:
        f.write(f"Total: {total_aggregate:.2f}")

if __name__ == "__main__":
    main()
EOF

    python3 -c '
import os
for i in range(50):
    filename = f"/home/user/sim_project/data/input_{i:03d}.txt"
    with open(filename, "w") as f:
        f.write("1.0\n2.0\n3.0\n")

with open("/home/user/sim_project/data/input_037.txt", "w") as f:
    f.write("800.0\n801.0\n800.0\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sim_project
    chmod -R 777 /home/user
