#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the buggy script
    cat << 'EOF' > /home/user/process_data.py
import math

def calc_stdev(filename):
    lines = open(filename).read().splitlines()
    n = len(lines)
    sum_x = 0.0
    sum_x2 = 0.0

    # Bug 1: Will crash on corrupted data
    # Bug 2: Naive variance calculation causes catastrophic cancellation
    for line in lines:
        val = float(line)
        sum_x += val
        sum_x2 += val * val

    mean = sum_x / n
    variance = (sum_x2 / n) - (mean * mean)

    # Due to floating point precision errors, variance might be slightly negative here
    return math.sqrt(variance)

if __name__ == '__main__':
    ans = calc_stdev('data.csv')
    with open('result.txt', 'w') as f:
        f.write(f"{ans:.4f}\n")
EOF

    # Create the setup script to run at container startup
    # This is required because background processes spawned in %post do not persist
    cat << 'EOF' > /setup.py
import os
import subprocess
import time

work_dir = "/home/user"
os.chdir(work_dir)

data_file = "data.csv"
if not os.path.exists(".setup_done"):
    with open(data_file, "w") as f:
        for i in range(200):
            if i == 100:
                f.write("CORRUPTED_DATA_ENTRY_MISSING_SENSOR\n")
            else:
                f.write(f"{1000000000.0 + i * 0.001:.3f}\n")

    # Spawn background process to hold the file open
    subprocess.Popen(["tail", "-f", data_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Give tail a moment to open the file
    time.sleep(0.5)

    # Delete the file
    os.remove(data_file)

    with open(".setup_done", "w") as f:
        f.write("done")
EOF

    # Add script to be sourced on container startup
    cat << 'EOF' > /.singularity.d/env/99-setup.sh
#!/bin/sh
python3 /setup.py
EOF
    chmod +x /.singularity.d/env/99-setup.sh

    chmod -R 777 /home/user
