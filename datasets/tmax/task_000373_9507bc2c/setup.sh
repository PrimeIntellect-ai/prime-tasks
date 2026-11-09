#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc netcat-openbsd
    pip3 install pytest numpy

    mkdir -p /app

    # Generate the dataset and truth files
    python3 -c '
import numpy as np

np.random.seed(42)
data = np.random.randint(0, 100, size=(100, 3))
np.savetxt("/app/dataset.csv", data, delimiter=",", fmt="%d")

# Expected cleaned dataset (removing rows 15, 42, 78)
clean_data = np.delete(data, [15, 42, 78], axis=0)
cov = np.cov(clean_data, rowvar=False, bias=True)
trace = np.trace(cov)

with open("/truth_cov.txt", "w") as f:
    f.write(" ".join([f"{x:.3f}" for x in cov.flatten()]) + "\n")
with open("/truth_trace.txt", "w") as f:
    f.write(f"{trace:.3f}\n")
'

    # Generate the audio file
    espeak -w /app/bug_report.wav "The corrupted rows are 15, 42, and 78."

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /truth_cov.txt /truth_trace.txt
