#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/filter.py"
CLEAN_DIR = "/home/user/data/clean"
EVIL_DIR = "/home/user/data/evil"


def run_filter(input_dir, output_dir):
    return subprocess.run(
        ["python3", SCRIPT_PATH, input_dir, output_dir],
        capture_output=True,
        text=True,
        timeout=60,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_adversarial_corpus():
    out_clean = "/tmp/out_clean_test"
    out_evil = "/tmp/out_evil_test"

    if os.path.exists(out_clean):
        shutil.rmtree(out_clean)
    if os.path.exists(out_evil):
        shutil.rmtree(out_evil)

    os.makedirs(out_clean)
    os.makedirs(out_evil)

    res_clean = run_filter(CLEAN_DIR, out_clean)
    assert res_clean.returncode == 0, f"Script failed on clean corpus. Error:\n{res_clean.stderr}"

    res_evil = run_filter(EVIL_DIR, out_evil)
    assert res_evil.returncode == 0, f"Script failed on evil corpus. Error:\n{res_evil.stderr}"

    clean_expected = set(os.listdir(CLEAN_DIR))
    clean_actual = set(os.listdir(out_clean))
    clean_missing = clean_expected - clean_actual

    evil_expected = set(os.listdir(EVIL_DIR))
    evil_actual = set(os.listdir(out_evil))
    evil_bypassed = evil_actual.intersection(evil_expected)

    errors = []
    if clean_missing:
        errors.append(f"{len(clean_missing)} of {len(clean_expected)} clean modified (missing from output): {', '.join(clean_missing)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_expected)} evil bypassed (copied to output): {', '.join(evil_bypassed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_mixed_corpus():
    rng = np.random.default_rng(731942)
    root = tempfile.mkdtemp(prefix="kinetics_eval_", dir="/tmp")
    input_dir = os.path.join(root, secrets.token_hex(8))
    output_dir = os.path.join(root, secrets.token_hex(8))
    os.makedirs(input_dir)
    os.makedirs(output_dir)

    expected_clean = set()
    expected_bytes = {}
    used_names = set()

    def fresh_name():
        while True:
            name = secrets.token_hex(12) + ".csv"
            if name not in used_names:
                used_names.add(name)
                return name

    # Generate fresh samples from the same decay/growth families as the
    # evaluation corpora, placing both classes in one neutrally named folder.
    specifications = []
    for _ in range(14):
        specifications.append((True, rng.uniform(5, 10), rng.uniform(0.5, 1.5), rng.uniform(0, 2)))
        specifications.append((False, rng.uniform(5, 10), rng.uniform(-0.5, -0.1), rng.uniform(0, 2)))
    rng.shuffle(specifications)

    for is_clean, amplitude, rate, offset in specifications:
        t = np.linspace(0, 10, 100)
        y = amplitude * np.exp(-rate * t) + offset + rng.normal(0, 0.1, 100)
        name = fresh_name()
        path = os.path.join(input_dir, name)
        np.savetxt(path, np.column_stack((t, y)), delimiter=",")
        if is_clean:
            expected_clean.add(name)
            with open(path, "rb") as f:
                expected_bytes[name] = f.read()

    # A non-CSV file must not be treated as a dataset or copied.
    with open(os.path.join(input_dir, secrets.token_hex(8) + ".txt"), "w") as f:
        f.write("not a kinetics dataset\n")

    result = run_filter(input_dir, output_dir)
    assert result.returncode == 0, f"Script failed on randomized mixed corpus. Error:\n{result.stderr}"

    actual = set(os.listdir(output_dir))
    assert actual == expected_clean, (
        f"Randomized mixed corpus was classified incorrectly. "
        f"Missing: {sorted(expected_clean - actual)}; unexpected: {sorted(actual - expected_clean)}"
    )

    for name, original in expected_bytes.items():
        output_path = os.path.join(output_dir, name)
        assert os.path.isfile(output_path), f"Expected output {name} is not a regular file"
        with open(output_path, "rb") as f:
            assert f.read() == original, f"Clean file {name} was modified instead of copied"

    shutil.rmtree(root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
