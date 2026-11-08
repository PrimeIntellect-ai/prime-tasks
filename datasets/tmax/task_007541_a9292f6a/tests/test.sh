#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import stat
import subprocess
import pytest

OPTIMIZER = "/home/user/optimizer.sh"


def run_optimizer(length, trace=False):
    command = ["bash"]
    if trace:
        command.append("-x")
    command.extend([OPTIMIZER, str(length)])
    result = subprocess.run(command, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, (
        f"optimizer.sh failed for L={length}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f"optimizer.sh must emit one numeric result, got: {result.stdout!r}"
    try:
        value = float(lines[0])
    except ValueError:
        pytest.fail(f"optimizer.sh emitted a non-numeric result: {lines[0]!r}")
    assert math.isfinite(value), f"optimizer.sh emitted a non-finite result: {value}"
    return value, result


def test_optimizer_is_repaired_and_executable():
    assert os.path.isfile(OPTIMIZER), f"Optimizer not found: {OPTIMIZER}"
    assert stat.S_ISREG(os.stat(OPTIMIZER).st_mode), "optimizer.sh is not a regular file"
    assert os.access(OPTIMIZER, os.X_OK), "optimizer.sh is not executable"

    with open(OPTIMIZER, "r", encoding="utf-8") as f:
        source = f.read()

    assert source.startswith("#!") and "bash" in source.splitlines()[0], "optimizer.sh must remain a Bash script"
    code = "\n".join(line.split("#", 1)[0] for line in source.splitlines())
    compact = re.sub(r"\s+", "", code)

    # Preserve the supplied biological scoring gradient and its gradient-descent update.
    assert "-2*($P-$L/10.0)" in compact, "The supplied scoring gradient was removed or changed"
    assert "$P+$step*$grad" in compact, "The gradient-descent update was removed or changed"
    assert "bc" in code, "The Bash optimizer no longer uses bc for floating-point optimization"

    # Specifically reject the supplied divergent adaptation, while allowing a decreasing
    # adaptation or a fixed sufficiently small step.
    for line in code.splitlines():
        if re.match(r"^\s*step\s*=", line) and "$step" in line and "1.5" in line:
            pytest.fail("The faulty step = step * 1.5 adaptation is still present")

    value, traced = run_optimizer(137, trace=True)
    assert abs(value - 13.7) <= 0.1, f"optimizer.sh did not converge for L=137: got {value}"
    bc_calls = re.findall(r"(?m)^\++\s+bc(?:\s|$)", traced.stderr)
    assert len(bc_calls) >= 20, "optimizer.sh did not execute the requested iterative bc-based optimization"


def test_optimizer_converges_on_derived_inputs():
    lengths = {7, 19, 83, 241}
    while len(lengths) < 8:
        lengths.add(5 + secrets.randbelow(490))

    for length in lengths:
        value, _ = run_optimizer(length)
        expected = length / 10.0
        assert abs(value - expected) <= 0.1, (
            f"optimizer.sh did not converge for L={length}: expected {expected}, got {value}"
        )


def test_venv_exists():
    """Check if the Python virtual environment is set up."""
    venv_dir = "/home/user/venv"
    python_exe = os.path.join(venv_dir, "bin", "python")
    assert os.path.isdir(venv_dir), f"Virtual environment directory not found: {venv_dir}"
    assert os.path.isfile(python_exe), f"Python executable not found in venv: {python_exe}"


def test_results_h5_exists():
    """Check if the results.h5 file was created."""
    results_file = "/home/user/results.h5"
    assert os.path.isfile(results_file), f"Results file not found: {results_file}"


def test_h5py_installed_and_results_correct():
    """Use the venv's Python to verify h5py, the HDF5 values, and optimizer agreement."""
    script = r'''
import subprocess
import sys
try:
    import h5py
except ImportError:
    print("h5py not installed in the virtual environment")
    sys.exit(1)

try:
    with h5py.File('/home/user/results.h5', 'r') as f:
        if '/optimal_P' not in f:
            print("Dataset '/optimal_P' not found in HDF5 file")
            sys.exit(1)

        data = list(f['/optimal_P'])
        expected = [1.0, 2.0, 3.0]

        if len(data) != len(expected):
            print(f"Dataset length mismatch: expected {len(expected)}, got {len(data)}")
            sys.exit(1)

        for d, e in zip(data, expected):
            if abs(d - e) > 0.1:
                print(f"Value mismatch: expected {expected}, got {data}")
                sys.exit(1)

    lengths = []
    current = []
    with open('/home/user/sequences.fasta', 'r') as fasta:
        for raw in fasta:
            line = raw.strip()
            if line.startswith('>'):
                if current:
                    lengths.append(sum(map(len, current)))
                    current = []
            elif line:
                current.append(line)
        if current:
            lengths.append(sum(map(len, current)))

    if len(lengths) != len(data):
        print(f"FASTA/result count mismatch: lengths={lengths}, data={data}")
        sys.exit(1)

    for length, stored in zip(lengths, data):
        proc = subprocess.run(
            ['/home/user/optimizer.sh', str(length)],
            capture_output=True, text=True, timeout=15
        )
        if proc.returncode != 0:
            print(f"optimizer.sh failed for FASTA length {length}: {proc.stderr}")
            sys.exit(1)
        try:
            produced = float(proc.stdout.strip())
        except ValueError:
            print(f"optimizer.sh returned non-numeric output for length {length}: {proc.stdout!r}")
            sys.exit(1)
        if abs(produced - float(stored)) > 0.1:
            print(f"Stored value {stored} does not match optimizer output {produced} for length {length}")
            sys.exit(1)

    print("Success")
except Exception as e:
    print(f"Error reading HDF5 file or running pipeline: {e}")
    sys.exit(1)
'''
    script_path = "/tmp/check_h5.py"
    with open(script_path, "w") as f:
        f.write(script)

    python_exe = "/home/user/venv/bin/python"
    result = subprocess.run([python_exe, script_path], capture_output=True, text=True)

    assert result.returncode == 0, f"Verification script failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert "Success" in result.stdout, f"Verification script did not succeed.\nSTDOUT: {result.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
