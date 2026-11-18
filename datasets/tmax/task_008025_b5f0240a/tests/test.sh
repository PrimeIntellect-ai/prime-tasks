#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_diffusion.py
import math
import os
import re
import subprocess
import time

SOURCE = "/home/user/diffusion.cpp"
EXECUTABLE = "/home/user/diffusion"
RESULTS = "/home/user/results.log"
REBUILT = "/tmp/verifier_diffusion"

# Derive the expected moments from the specified initial block and diffusion.
block_size = 10
concentration = 100.0
steps = 1000
D = 0.1
dt = 1.0
expected = {
    "M": block_size * block_size * concentration,
    "mu_x": sum(range(400, 410)) / block_size,
    "mu_y": sum(range(600, 610)) / block_size,
    "var_x": (block_size * block_size - 1) / 12.0 + 2.0 * D * dt * steps,
    "var_y": (block_size * block_size - 1) / 12.0 + 2.0 * D * dt * steps,
    "cov_xy": 0.0,
}
KEYS = ["M", "mu_x", "mu_y", "var_x", "var_y", "cov_xy"]


def validate_results():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."
    with open(RESULTS, "r", encoding="utf-8") as f:
        content = f.read()

    # Retain the original key/value and numerical assertions.
    results = {}
    for line in content.strip().split("\n"):
        if "=" in line:
            key, val = line.split("=", 1)
            try:
                results[key.strip()] = float(val.strip())
            except ValueError:
                raise AssertionError(f"Could not parse value for {key}: {val}")

    for key, expected_val in expected.items():
        assert key in results, f"Missing key {key} in results.log"
        actual = results[key]
        assert math.isfinite(actual), f"Value for {key} is not finite"
        assert abs(actual - expected_val) <= 0.05, \
            f"Value for {key} is {actual}, expected ~{expected_val}"

    # The instruction requires exactly six ordered lines with two decimals.
    pattern = "\\n".join(re.escape(k) + r"=-?\d+\.\d{2}" for k in KEYS) + r"\n?"
    assert re.fullmatch(pattern, content), \
        "results.log must contain exactly the six required ordered lines with two decimal places"


def assert_openmp_binary(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF executable"
    symbols = subprocess.run(
        ["nm", "-D", path], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=15
    ).stdout
    assert "GOMP_" in symbols or "omp_" in symbols, \
        f"{path} does not contain OpenMP runtime references"


def run_and_measure(path):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    env["OMP_DYNAMIC"] = "FALSE"
    proc = subprocess.Popen(
        [path], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    deadline = time.monotonic() + 180
    max_threads = 0
    max_cpu_ticks = 0
    while proc.poll() is None:
        if time.monotonic() > deadline:
            proc.kill()
            proc.wait()
            raise AssertionError(f"{path} timed out")
        task_dir = f"/proc/{proc.pid}/task"
        try:
            tids = os.listdir(task_dir)
            max_threads = max(max_threads, len(tids))
            total = 0
            for tid in tids:
                try:
                    with open(f"{task_dir}/{tid}/stat", "r") as f:
                        stat = f.read()
                    fields = stat[stat.rfind(")") + 2:].split()
                    total += int(fields[11]) + int(fields[12])
                except (FileNotFoundError, ProcessLookupError):
                    pass
            max_cpu_ticks = max(max_cpu_ticks, total)
        except (FileNotFoundError, ProcessLookupError):
            pass
        time.sleep(0.005)

    stdout, stderr = proc.communicate()
    assert proc.returncode == 0, \
        f"{path} exited with {proc.returncode}: {stderr.decode(errors='replace')[-2000:]}"
    assert max_threads >= 2, "The simulation did not execute with multiple OpenMP threads"
    assert max_cpu_ticks >= 20, \
        "The executable performed too little computation to have simulated 1000 full-grid steps"
    validate_results()


# Preserve the original artifact assertions and validate the agent-produced result.
assert os.path.isfile(SOURCE), "Source code file /home/user/diffusion.cpp is missing."
assert os.path.isfile(EXECUTABLE), "Executable /home/user/diffusion is missing."
assert os.access(EXECUTABLE, os.X_OK), "/home/user/diffusion is not executable."
assert os.path.isfile(RESULTS), "Results file /home/user/results.log is missing."
validate_results()

with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
    source_text = f.read()
assert re.search(r"(?m)^\s*#\s*pragma\s+omp\s+parallel\b", source_text), \
    "Source does not contain an OpenMP parallel region"

# Execute the submitted executable rather than trusting the pre-existing log.
assert_openmp_binary(EXECUTABLE)
run_and_measure(EXECUTABLE)

# Independently prove that the submitted source compiles with the required flags
# and that the resulting program performs the same simulation.
compile_result = subprocess.run(
    ["g++", "-O3", "-fopenmp", SOURCE, "-o", REBUILT],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
)
assert compile_result.returncode == 0, \
    f"diffusion.cpp failed to compile with -O3 -fopenmp:\n{compile_result.stderr[-4000:]}"
assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK), \
    "Recompiled program is not executable"
assert_openmp_binary(REBUILT)
run_and_measure(REBUILT)
PY_EOF

if python3 /tmp/verify_diffusion.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
