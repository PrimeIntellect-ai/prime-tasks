#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import secrets
import subprocess

import pytest


def test_sim_executable():
    sim_exec = "/app/simkit-1.2/sim"
    assert os.path.exists(sim_exec), f"Executable {sim_exec} was not built."
    assert os.access(sim_exec, os.X_OK), f"File {sim_exec} is not executable."


def test_sim_rebuilds_and_runs():
    build_dir = "/app/simkit-1.2"
    sim_exec = os.path.join(build_dir, "sim")
    source = os.path.join(build_dir, "sim.c")
    makefile = os.path.join(build_dir, "Makefile")

    assert os.path.isfile(source), f"Source {source} is missing."
    assert os.path.isfile(makefile), f"Makefile {makefile} is missing."

    os.unlink(sim_exec)
    build = subprocess.run(
        ["make", "-B"], cwd=build_dir, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, (
        f"make failed with exit code {build.returncode}:\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(sim_exec), "make did not produce the sim executable."
    assert os.access(sim_exec, os.X_OK), "The rebuilt sim is not executable."
    with open(sim_exec, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The rebuilt sim is not a compiled ELF executable."

    run = subprocess.run([sim_exec], capture_output=True, text=True, timeout=10)
    assert run.returncode == 0, f"The rebuilt sim failed: {run.stderr}"
    lines = run.stdout.splitlines()
    assert len(lines) == 10, f"sim should print 10 readings, but printed {len(lines)}."
    try:
        values = [float(line) for line in lines]
    except ValueError as exc:
        pytest.fail(f"sim emitted a non-numeric reading: {exc}")
    assert all(math.isfinite(v) and 0.0 <= v <= 10.0 for v in values), (
        "sim emitted an invalid reading."
    )


def test_classifier_script_exists():
    script = "/home/user/classifier.sh"
    assert os.path.exists(script), f"Script {script} does not exist."
    assert os.access(script, os.X_OK), f"Script {script} is not executable."


def classify_all(script, cases):
    failures = []
    for path, expected in cases:
        try:
            result = subprocess.run([script, path], capture_output=True, timeout=10)
        except subprocess.TimeoutExpired:
            failures.append(f"{os.path.basename(path)} timed out")
            continue
        if result.returncode != expected:
            failures.append(
                f"{os.path.basename(path)} returned {result.returncode}, expected {expected}"
            )
    return failures


def test_classifier_accuracy():
    script = "/home/user/classifier.sh"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = sorted(glob.glob(os.path.join(clean_dir, "*.txt")))
    evil_files = sorted(glob.glob(os.path.join(evil_dir, "*.txt")))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failures = []
    for f in clean_files:
        res = subprocess.run([script, f], capture_output=True)
        if res.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        res = subprocess.run([script, f], capture_output=True)
        if res.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if evil_failures:
        error_msgs.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_failures)
        )
    if clean_failures:
        error_msgs.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): "
            + ", ".join(clean_failures)
        )
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_classifier_on_fresh_neutral_paths(tmp_path):
    script = "/home/user/classifier.sh"
    sample_dir = tmp_path / secrets.token_hex(12)
    sample_dir.mkdir()

    rng = random.Random(secrets.randbits(128))
    cases = []
    for expected, stddev in ((0, 1.0), (1, 5.0)):
        for _ in range(32):
            path = sample_dir / (secrets.token_hex(16) + ".dat")
            with open(path, "w") as f:
                for _ in range(100):
                    f.write(f"{rng.gauss(10.0, stddev):.8f}\n")
            cases.append((str(path), expected))

    rng.shuffle(cases)
    failures = classify_all(script, cases)
    assert not failures, "Fresh-corpus classification failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
