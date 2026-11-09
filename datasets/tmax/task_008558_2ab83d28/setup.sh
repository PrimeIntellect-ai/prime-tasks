#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the initial dataset files using Python to ensure correct encodings
    python3 -c '
import os

base_dir = "/home/user/dataset_raw"
os.makedirs(os.path.join(base_dir, "alpha"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "beta"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "gamma"), exist_ok=True)

log_content = """---
Experiment: Alpha Run 1
Dataset-ID: 1001
Date: 2021-05-12
Status: SUCCESS
---
Experiment: Beta Run 2
Dataset-ID: 2002
Date: 2021-06-15
Status: FAILED
---
Experiment: Gamma Run 3
Dataset-ID: 3003
Date: 2021-07-20
Status: SUCCESS
---
Experiment: Delta Run 4
Dataset-ID: 4004
Date: 2021-08-25
Status: SUCCESS
---"""

with open(os.path.join(base_dir, "experiments.log"), "w") as f:
    f.write(log_content)

# File 1: SUCCESS, UTF-16, > 50 bytes
file_1001_content = "ID,Measurement,Notes\n1001,0.992,This is a successful run with some extra padding to ensure it exceeds the fifty byte minimum limit we established for valid files.\n"
with open(os.path.join(base_dir, "alpha", "data_1001.dat"), "w", encoding="utf-16") as f:
    f.write(file_1001_content)

# File 2: FAILED, UTF-8, > 50 bytes (Should be ignored based on log)
file_2002_content = "ID,Measurement,Notes\n2002,0.112,This run failed so it should not be included in the final clean dataset regardless of its size or encoding.\n"
with open(os.path.join(base_dir, "beta", "data_2002.dat"), "w", encoding="utf-8") as f:
    f.write(file_2002_content)

# File 3: SUCCESS, ISO-8859-1, > 50 bytes (Contains special character)
file_3003_content = "ID,Measurement,Notes\n3003,0.875,Successful run from the café. Padding added to ensure size exceeds fifty bytes.\n"
with open(os.path.join(base_dir, "gamma", "dataset_3003.dat"), "w", encoding="iso-8859-1") as f:
    f.write(file_3003_content)

# File 4: SUCCESS, UTF-8, < 50 bytes (Should be ignored based on size)
file_4004_content = "ID,Val\n4004,1" # Very short
with open(os.path.join(base_dir, "gamma", "data_4004.dat"), "w", encoding="utf-8") as f:
    f.write(file_4004_content)
'

    chmod -R 777 /home/user
