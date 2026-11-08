#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

os.makedirs("/home/user/app", exist_ok=True)
os.makedirs("/home/user/data", exist_ok=True)
os.makedirs("/home/user/logs", exist_ok=True)

for i in range(50):
    with open(f"/home/user/data/data_{i:02d}.csv", "w") as f:
        if i == 37:
            f.write("-999.0\n1.0\n2.0\n")
        else:
            f.write("1.0\n2.0\n3.0\n")

script_content = """import sys
import os
import csv
import faulthandler
import ctypes

faulthandler.enable()

def compute_stats(filepath):
    with open(filepath, "r") as f:
        data = [float(line.strip()) for line in f]

    n = len(data)
    mean = sum(data) / n
    var = sum((x - mean)**2 for x in data) / n

    # Bug: hardcoded anomaly for specific corrupted value
    if data[0] == -999.0:
        var = -42.42
        print(f"Processed {filepath}: Variance={var}")
        sys.stdout.flush()
        # Cause segfault
        ctypes.string_at(0)

    print(f"Processed {filepath}: Variance={var}")

if __name__ == "__main__":
    for i in range(50):
        compute_stats(f"/home/user/data/data_{i:02d}.csv")
"""
with open("/home/user/app/stats_calculator.py", "w") as f:
    f.write(script_content)

job_log_content = ""
for i in range(37):
    job_log_content += f"Processed /home/user/data/data_{i:02d}.csv: Variance=0.6666666666666666\n"
job_log_content += "Processed /home/user/data/data_37.csv: Variance=-42.42\n"
job_log_content += "Fatal Python error: Segmentation fault\n\n"
job_log_content += "Current thread 0x00007f8b9c123456 (most recent call first):\n"
job_log_content += "  File \"/home/user/app/stats_calculator.py\", line 21 in compute_stats\n"
job_log_content += "  File \"/home/user/app/stats_calculator.py\", line 27 in <module>\n"

with open("/home/user/logs/job.log", "w") as f:
    f.write(job_log_content)

strace_log_content = """
openat(AT_FDCWD, "/home/user/data/data_36.csv", O_RDONLY|O_CLOEXEC) = 3
read(3, "1.0\\n2.0\\n3.0\\n", 4096) = 12
close(3) = 0
write(1, "Processed /home/user/data/data_36.csv: Variance=0.6666666666666666\\n", 67) = 67
openat(AT_FDCWD, "/home/user/data/data_37.csv", O_RDONLY|O_CLOEXEC) = 3
read(3, "-999.0\\n1.0\\n2.0\\n", 4096) = 15
close(3) = 0
write(1, "Processed /home/user/data/data_37.csv: Variance=-42.42\\n", 55) = 55
--- SIGSEGV {si_signo=SIGSEGV, si_code=SEGV_MAPERR, si_addr=NULL} ---
+++ killed by SIGSEGV (core dumped) +++
"""
with open("/home/user/logs/strace.log", "w") as f:
    f.write(strace_log_content)
'

    chmod -R 777 /home/user
