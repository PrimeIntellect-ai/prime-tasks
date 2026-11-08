#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess


def run_backend(python_bin):
    result = subprocess.run(
        [python_bin, "/home/user/app/backend.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"backend.py exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_result():
    filepath = "/home/user/result.txt"
    assert os.path.isfile(filepath), f"File missing: {filepath}"
    with open(filepath, "r") as f:
        content = f.read().strip()
    try:
        return float(content)
    except ValueError:
        raise AssertionError(f"Content of {filepath} is not a valid float: {content}")


def determinant(matrix):
    if len(matrix) == 1:
        return matrix[0][0]
    total = 0
    for col, value in enumerate(matrix[0]):
        minor = [row[:col] + row[col + 1:] for row in matrix[1:]]
        total += ((-1) ** col) * value * determinant(minor)
    return total


def test_complete_task():
    # Preserve the original crashing-ID assertions.
    ids_path = "/home/user/crashing_ids.txt"
    assert os.path.isfile(ids_path), f"File missing: {ids_path}"
    with open(ids_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_ids = {"REQ-003", "REQ-005", "REQ-008"}
    actual_ids = set(lines)
    assert actual_ids == expected_ids, f"Expected crashing IDs {expected_ids}, but got {actual_ids}"
    assert len(lines) == len(expected_ids), "There are duplicate or extra entries in crashing_ids.txt"

    # Preserve the original virtual-environment assertions and verify that its
    # interpreter can actually load the installed dependency from the venv.
    venv_dir = "/home/user/venv"
    python_bin = os.path.join(venv_dir, "bin", "python")
    assert os.path.isdir(venv_dir), f"Virtual environment directory missing: {venv_dir}"
    assert os.path.isfile(python_bin) or os.path.islink(python_bin), f"Python executable missing in venv: {python_bin}"

    probe = subprocess.run(
        [python_bin, "-c", "import json,sys,numpy; print(json.dumps({'prefix':sys.prefix,'numpy':numpy.__file__}))"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert probe.returncode == 0, f"numpy is not usable in the virtual environment: {probe.stderr}"
    info = json.loads(probe.stdout.strip().splitlines()[-1])
    assert os.path.realpath(info["prefix"]) == os.path.realpath(venv_dir), "Interpreter is not running as the requested virtual environment"
    assert os.path.realpath(info["numpy"]).startswith(os.path.realpath(venv_dir) + os.sep), "numpy was not installed inside /home/user/venv"
    pip_check = subprocess.run([python_bin, "-m", "pip", "check"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
    assert pip_check.returncode == 0, f"Virtual-environment dependencies are inconsistent: {pip_check.stdout}{pip_check.stderr}"

    # Preserve the original source-level assertion.
    backend_path = "/home/user/app/backend.py"
    assert os.path.isfile(backend_path), f"File missing: {backend_path}"
    with open(backend_path, "r") as f:
        content = f.read()
    assert "try:" in content and "except" in content, "backend.py does not appear to have try/except error handling added"

    payload_path = "/home/user/data/payload.jsonl"
    result_path = "/home/user/result.txt"
    with open(payload_path, "rb") as f:
        original_payload = f.read()

    try:
        # Actually execute the submitted backend on the supplied payload. Remove
        # any prewritten answer first so the process must create the result.
        if os.path.exists(result_path):
            os.remove(result_path)
        run_backend(python_bin)
        result_val = read_result()
        assert abs(result_val - 27.0) < 1e-6, f"Expected result to be 27.0, but got {result_val}"

        # Exercise the implementation on fresh data with valid records before
        # and after every invalid category. The expected answer is derived here.
        rng = random.SystemRandom()
        while True:
            valid_matrices = [
                [[rng.randint(-8, 8), rng.randint(-8, 8)], [rng.randint(-8, 8), rng.randint(-8, 8)]],
                [[rng.randint(-5, 5) for _ in range(3)] for _ in range(3)],
                [[rng.randint(-9, 9)]],
                [[rng.randint(-6, 6), rng.randint(-6, 6)], [rng.randint(-6, 6), rng.randint(-6, 6)]],
            ]
            expected = sum(determinant(matrix) for matrix in valid_matrices)
            if expected not in (0, 27):
                break

        records = [
            {"id": "DYN-VALID-1", "matrix": valid_matrices[0]},
            {"id": "DYN-BAD-TYPE", "matrix": [[1, "not-a-number"], [2, 3]]},
            {"id": "DYN-VALID-2", "matrix": valid_matrices[1]},
            {"id": "DYN-NON-SQUARE", "matrix": [[1, 2, 3], [4, 5, 6]]},
            {"id": "DYN-VALID-3", "matrix": valid_matrices[2]},
            {"id": "DYN-CORRUPTED", "matrix": "corrupted"},
            {"id": "DYN-RAGGED", "matrix": [[1, 2], [3]]},
            {"id": "DYN-VALID-4", "matrix": valid_matrices[3]},
        ]
        with open(payload_path, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")
        if os.path.exists(result_path):
            os.remove(result_path)
        run_backend(python_bin)
        dynamic_result = read_result()
        assert abs(dynamic_result - float(expected)) < 1e-6, (
            f"Backend did not skip invalid entries and sum all valid determinants: "
            f"expected {float(expected)}, got {dynamic_result}"
        )
    finally:
        with open(payload_path, "wb") as f:
            f.write(original_payload)
        if os.path.exists(result_path):
            os.remove(result_path)
        subprocess.run([python_bin, backend_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
