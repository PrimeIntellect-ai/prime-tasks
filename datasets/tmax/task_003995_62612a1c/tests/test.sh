#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import shutil
import subprocess
import tempfile

import pytest

HOME = "/home/user"
MODEL = os.path.join(HOME, "sim_model")
ORIGINAL_LINES = [
    "GAMMA=0.5",
    "DELTA=0.4",
    "ALPHA=0.9",
    "EPSILON=0.1",
    "ZETA=0.2",
    "ETA=0.3",
    "BETA=0.1",
    "THETA=0.8",
    "IOTA=0.9",
    "KAPPA=1.0",
]


def run_model(lines=None):
    with tempfile.TemporaryDirectory() as workdir:
        if lines is not None:
            with open(os.path.join(workdir, "config.txt"), "w") as f:
                if lines:
                    f.write("\n".join(lines) + "\n")
        result = subprocess.run(
            [MODEL], cwd=workdir, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        return result.returncode


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def script_command(path):
    ext = os.path.splitext(path)[1].lower()
    interpreters = {
        ".py": "python3",
        ".sh": "bash",
        ".bash": "bash",
        ".pl": "perl",
        ".rb": "ruby",
        ".js": "node",
    }
    if ext in interpreters and shutil.which(interpreters[ext]):
        return [interpreters[ext], path]

    try:
        with open(path, "rb") as f:
            first = f.readline(256)
    except OSError:
        return None
    if first.startswith(b"#!") and os.access(path, os.X_OK):
        return [path]
    return None


def test_sim_model_executable_exists():
    path = MODEL
    assert os.path.isfile(path), f"Executable {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sim_model must be a compiled executable."

    assert run_model(None) == 2, "sim_model must report a missing config.txt with exit code 2."
    assert run_model(ORIGINAL_LINES) == 1, "The original failing configuration must exit with code 1."


def test_delta_debugging_script_executes_and_generates_minimum():
    excluded = {
        "sim_model.c", "sim_model", "config.txt", "min_config.txt",
        "fixed_config.txt"
    }
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            if root == HOME and name in excluded:
                continue
            path = os.path.join(root, name)
            if os.path.isfile(path):
                command = script_command(path)
                if command is not None:
                    priority = 0 if ("delta" in name.lower() or name.lower().startswith("dd")) else 1
                    candidates.append((priority, path, command))

    assert candidates, "No runnable delta-debugging script was found under /home/user."
    candidates.sort()

    min_path = os.path.join(HOME, "min_config.txt")
    generated = False
    errors = []
    for _, path, command in candidates:
        try:
            if os.path.exists(min_path):
                os.remove(min_path)
            result = subprocess.run(
                command, cwd=HOME, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=60
            )
            if os.path.isfile(min_path):
                lines = read_nonempty_lines(min_path)
                if run_model(lines) == 1:
                    generated = True
                    break
            errors.append(f"{path}: exit {result.returncode}, no failing min_config.txt generated")
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(f"{path}: {exc}")

    assert generated, "No delta-debugging script generated a failing min_config.txt when executed. " + "; ".join(errors)


def test_min_config_txt():
    path = "/home/user/min_config.txt"
    assert os.path.isfile(path), f"File {path} is missing."

    lines = read_nonempty_lines(path)

    assert len(lines) == 2, f"Expected exactly 2 lines in min_config.txt, found {len(lines)}."
    assert "ALPHA=0.9" in lines, "min_config.txt is missing 'ALPHA=0.9'."
    assert "BETA=0.1" in lines, "min_config.txt is missing 'BETA=0.1'."

    assert run_model(lines) == 1, "min_config.txt does not trigger convergence failure."
    for size in range(len(lines)):
        for subset in itertools.combinations(lines, size):
            assert run_model(list(subset)) != 1, \
                f"min_config.txt is not minimal; subset {subset!r} still fails."

    minimum_failing_sets = []
    for size in range(len(ORIGINAL_LINES) + 1):
        for subset in itertools.combinations(ORIGINAL_LINES, size):
            if run_model(list(subset)) == 1:
                minimum_failing_sets.append(set(subset))
        if minimum_failing_sets:
            break
    assert set(lines) in minimum_failing_sets, \
        "min_config.txt is not an absolute minimum failing subset of the original configuration."


def test_fixed_config_txt():
    path = "/home/user/fixed_config.txt"
    assert os.path.isfile(path), f"File {path} is missing."

    lines = read_nonempty_lines(path)

    assert len(lines) == 10, f"Expected exactly 10 lines in fixed_config.txt, found {len(lines)}."
    assert "BETA=0.5" in lines, "fixed_config.txt is missing 'BETA=0.5' or it is incorrectly formatted."
    assert "ALPHA=0.9" in lines, "fixed_config.txt is missing 'ALPHA=0.9'."
    assert "BETA=0.1" not in lines, "fixed_config.txt should not contain 'BETA=0.1'."

    expected_other_lines = [
        "GAMMA=0.5",
        "DELTA=0.4",
        "EPSILON=0.1",
        "ZETA=0.2",
        "ETA=0.3",
        "THETA=0.8",
        "IOTA=0.9",
        "KAPPA=1.0"
    ]
    for line in expected_other_lines:
        assert line in lines, f"fixed_config.txt is missing original line '{line}'."

    expected_fixed = ["BETA=0.5" if line == "BETA=0.1" else line for line in ORIGINAL_LINES]
    assert lines == expected_fixed, \
        "fixed_config.txt must be identical to the original configuration except for BETA=0.5."
    assert run_model(lines) == 0, "fixed_config.txt must restore convergence with exit code 0."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
