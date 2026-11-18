#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import itertools
import json
import os
import secrets
import shutil
import stat
import subprocess

import pytest

SCRIPT_PATH = "/home/user/optimize.sh"
CSV_PATH = "/home/user/best_mapping.csv"
SEQUENCE_PATH = "/home/user/sequence.txt"
NOTEBOOK_PATH = "/home/user/calc_fft.ipynb"
LOG_PATH = "/tmp/verifier_papermill_calls.jsonl"


def get_max_score_and_perms():
    try:
        import numpy as np
    except ImportError:
        pytest.fail("numpy is not installed. The task requires installing numpy.")

    if not os.path.isfile(SEQUENCE_PATH):
        pytest.fail(f"Missing sequence file: {SEQUENCE_PATH}")

    with open(SEQUENCE_PATH, "r") as f:
        seq = f.read().strip()

    N = len(seq)
    target_idx = int(np.round(N / 3.0))
    max_score = -1.0
    best_perms = []

    for perm in itertools.permutations([1, 2, 3, 4]):
        mapping = {"A": perm[0], "C": perm[1], "G": perm[2], "T": perm[3]}
        num_seq = np.array([mapping.get(base, 0) for base in seq])
        fft_vals = np.abs(np.fft.fft(num_seq)) ** 2
        signal = fft_vals[target_idx]
        noise = np.mean(fft_vals[1:])
        score = signal / noise if noise > 0 else 0

        if score > max_score + 1e-6:
            max_score = score
            best_perms = [perm]
        elif abs(score - max_score) <= 1e-6:
            best_perms.append(perm)

    return max_score, best_perms


def make_challenge_sequence():
    alphabet = "ACGT"
    raw = secrets.token_bytes(96)
    seq = "".join(alphabet[b % 4] for b in raw)
    # Guarantee that every mapped nucleotide is represented.
    return "ACGT" + seq[4:]


def install_papermill_wrapper():
    command = shutil.which("papermill")
    assert command is not None, "papermill command is not installed."
    real_path = os.path.realpath(command)
    backup_path = "/tmp/verifier-real-papermill"
    shutil.copy2(real_path, backup_path)

    original_mode = stat.S_IMODE(os.stat(real_path).st_mode)
    wrapper = r'''#!/usr/bin/env python3
import ast
import json
import os
import subprocess
import sys

args = sys.argv[1:]
result = subprocess.run([os.environ["VERIFIER_REAL_PAPERMILL"]] + args)
record = {"args": args, "returncode": result.returncode, "parameters": None}
try:
    import nbformat
    nb = nbformat.read("/tmp/out.ipynb", as_version=4)
    values = {}
    for cell in nb.cells:
        if "injected-parameters" not in cell.get("metadata", {}).get("tags", []):
            continue
        tree = ast.parse(cell.get("source", ""))
        for node in tree.body:
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                name = node.targets[0].id
                if name in {"valA", "valC", "valG", "valT"}:
                    values[name] = ast.literal_eval(node.value)
    if set(values) == {"valA", "valC", "valG", "valT"}:
        record["parameters"] = values
except Exception as exc:
    record["inspection_error"] = repr(exc)
with open(os.environ["VERIFIER_PAPERMILL_LOG"], "a") as f:
    f.write(json.dumps(record) + "\n")
sys.exit(result.returncode)
'''
    with open(real_path, "w") as f:
        f.write(wrapper)
    os.chmod(real_path, 0o755)
    return real_path, backup_path, original_mode


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    # Preserve the original existence and executable assertions before executing it.
    assert os.path.isfile(CSV_PATH), f"Missing required file: {CSV_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Missing required file: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."
    assert os.path.isfile(NOTEBOOK_PATH), f"Missing required file: {NOTEBOOK_PATH}"

    with open(SEQUENCE_PATH, "w") as f:
        f.write(make_challenge_sequence() + "\n")

    for path in (CSV_PATH, "/home/user/current_score.txt", "/tmp/out.ipynb", LOG_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    real_path, backup_path, original_mode = install_papermill_wrapper()
    env = os.environ.copy()
    env["VERIFIER_REAL_PAPERMILL"] = backup_path
    env["VERIFIER_PAPERMILL_LOG"] = LOG_PATH

    try:
        completed = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=300,
        )
    finally:
        shutil.copyfile(backup_path, real_path)
        os.chmod(real_path, original_mode)

    assert completed.returncode == 0, (
        f"optimize.sh failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    yield


def test_required_packages_installed():
    import numpy  # noqa: F401
    import scipy  # noqa: F401
    import papermill  # noqa: F401
    assert shutil.which("jupyter") is not None, "jupyter is not installed."


def test_best_mapping_exists():
    assert os.path.isfile(CSV_PATH), f"Missing required file: {CSV_PATH}"


def test_optimize_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Missing required file: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_all_permutations_were_evaluated_with_papermill():
    assert os.path.isfile(LOG_PATH), "optimize.sh did not invoke the papermill command."
    with open(LOG_PATH) as f:
        calls = [json.loads(line) for line in f if line.strip()]

    assert len(calls) == 24, f"Expected exactly 24 papermill evaluations, observed {len(calls)}."
    observed = []
    for call in calls:
        assert call["returncode"] == 0, "A papermill notebook evaluation failed."
        args = call["args"]
        assert NOTEBOOK_PATH in args, "papermill was not given /home/user/calc_fft.ipynb."
        assert "/tmp/out.ipynb" in args, "papermill did not write /tmp/out.ipynb."
        params = call.get("parameters")
        assert params is not None, "Could not verify the parameters injected into a notebook evaluation."
        observed.append(tuple(int(params[name]) for name in ("valA", "valC", "valG", "valT")))

    expected = set(itertools.permutations([1, 2, 3, 4]))
    assert set(observed) == expected and len(observed) == len(set(observed)), (
        "papermill must evaluate every permutation of {1,2,3,4} exactly once."
    )


def test_best_mapping_correctness():
    assert os.path.isfile(CSV_PATH), f"Missing required file: {CSV_PATH}"
    max_score, best_perms = get_max_score_and_perms()

    with open(CSV_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, "The best_mapping.csv file is empty."
    parts = lines[-1].split(",")
    assert len(parts) == 5, f"Expected 5 comma-separated values in best_mapping.csv, but got {len(parts)}."

    try:
        valA, valC, valG, valT = map(int, parts[:4])
        score = float(parts[4])
    except ValueError:
        pytest.fail("Could not parse the values in best_mapping.csv as integers and a float.")

    actual_perm = (valA, valC, valG, valT)
    assert actual_perm in best_perms, f"The permutation {actual_perm} is not one of the optimal permutations."
    assert abs(score - max_score) < 1e-2, f"The score {score} does not match the expected maximum score {max_score}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
