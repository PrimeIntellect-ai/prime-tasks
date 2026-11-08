#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import math
import os
import stat
import subprocess
import h5py
import pytest

JSON_PATH = "/home/user/alignment_stats.json"
H5_PATH = "/home/user/assay_data.h5"


def load_results():
    assert os.path.exists(JSON_PATH), f"File {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"Path {JSON_PATH} is not a file."
    with open(JSON_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Invalid JSON format in alignment_stats.json.")

    required_keys = ["observed_mms", "background_mean", "background_std", "z_score"]
    for key in required_keys:
        assert key in results, f"Missing key in JSON output: {key}"
    return results


def test_alignment_stats_json():
    results = load_results()

    # Preserve the original checks for the supplied assay.
    EXPECTED_OBSERVED = 5
    EXPECTED_MEAN = 3.425
    EXPECTED_STD = 0.610

    assert results["observed_mms"] == EXPECTED_OBSERVED, \
        f"Incorrect observed_mms. Expected {EXPECTED_OBSERVED}, got {results['observed_mms']}"
    assert abs(results["background_mean"] - EXPECTED_MEAN) <= 0.05, \
        f"Background mean out of bounds. Got {results['background_mean']}, expected ~{EXPECTED_MEAN}"
    assert abs(results["background_std"] - EXPECTED_STD) <= 0.05, \
        f"Background std out of bounds. Got {results['background_std']}, expected ~{EXPECTED_STD}"

    expected_z = (results["observed_mms"] - results["background_mean"]) / results["background_std"]
    assert abs(results["z_score"] - expected_z) <= 0.05, \
        f"Z-score mathematically incorrect based on provided mean/std. Got {results['z_score']}, expected ~{expected_z}"


def mms(target, primer):
    width = len(primer)
    return max(
        sum(a == b for a, b in zip(primer, target[i:i + width]))
        for i in range(len(target) - width + 1)
    )


def exact_background(target_length, primer):
    count = 0
    total = 0
    total_sq = 0
    for letters in itertools.product("ACGT", repeat=target_length):
        score = mms("".join(letters), primer)
        count += 1
        total += score
        total_sq += score * score
    mean = total / count
    variance = total_sq / count - mean * mean
    return mean, math.sqrt(max(0.0, variance))


def write_assay(target, primer):
    if os.path.isdir(H5_PATH):
        pytest.fail(f"Submission replaced {H5_PATH} with a directory")
    with h5py.File(H5_PATH, "w") as f:
        f.create_dataset("target", data=target.encode("ascii"))
        f.create_dataset("primer", data=primer.encode("ascii"))


def candidate_commands():
    commands = []
    suffix_interpreters = {
        ".py": ["python3"],
        ".sh": ["bash"],
        ".pl": ["perl"],
        ".rb": ["ruby"],
        ".js": ["node"],
        ".php": ["php"],
    }
    excluded = {os.path.realpath(H5_PATH), os.path.realpath(JSON_PATH)}

    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__", ".git"}]
        for name in files:
            path = os.path.join(root, name)
            real = os.path.realpath(path)
            if real in excluded or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > 5 * 1024 * 1024:
                    continue
                mode = os.stat(path).st_mode
                suffix = os.path.splitext(name)[1].lower()
                if suffix in suffix_interpreters:
                    commands.append(suffix_interpreters[suffix] + [path])
                    continue
                with open(path, "rb") as f:
                    head = f.read(160)
                if head.startswith(b"#!"):
                    line = head.splitlines()[0].decode("utf-8", "ignore").lower()
                    if "python" in line:
                        commands.append(["python3", path])
                    elif "bash" in line or line.endswith("/sh") or " sh" in line:
                        commands.append(["bash", path])
                    else:
                        commands.append([path])
                elif mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
                    commands.append([path])
            except OSError:
                continue
    return commands


def validate_hidden_result(target, primer, expected_mean, expected_std):
    results = load_results()
    observed = mms(target, primer)
    assert results["observed_mms"] == observed, \
        f"Script did not compute observed MMS from a replacement assay: expected {observed}, got {results['observed_mms']}"

    for key in ("background_mean", "background_std", "z_score"):
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), \
            f"{key} must be numeric"
        assert math.isfinite(results[key]), f"{key} must be finite"

    assert abs(results["background_mean"] - expected_mean) <= 0.05, \
        f"Background mean for replacement assay is incorrect: got {results['background_mean']}, expected ~{expected_mean}"
    assert abs(results["background_std"] - expected_std) <= 0.05, \
        f"Background std for replacement assay is incorrect: got {results['background_std']}, expected ~{expected_std}"
    assert results["background_std"] > 0
    reported_z = (results["observed_mms"] - results["background_mean"]) / results["background_std"]
    assert abs(results["z_score"] - reported_z) <= 0.05, \
        f"Z-score is inconsistent with the script's mean and std: got {results['z_score']}, expected ~{reported_z}"


def test_script_executes_and_reads_assay():
    commands = candidate_commands()
    assert commands, "No runnable analysis script was found under /home/user"

    fixtures = [
        ("TTTTACGTT", "ACG"),
        ("CCCCAAAG", "TATA"),
    ]
    expected = [(t, p, *exact_background(len(t), p)) for t, p in fixtures]

    with open(H5_PATH, "rb") as f:
        original_h5 = f.read()
    with open(JSON_PATH, "rb") as f:
        original_json = f.read()

    errors = []
    try:
        for command in commands:
            passed = True
            for target, primer, expected_mean, expected_std in expected:
                try:
                    write_assay(target, primer)
                    if os.path.lexists(JSON_PATH):
                        os.remove(JSON_PATH)
                    completed = subprocess.run(
                        command,
                        cwd="/home/user",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=180,
                    )
                    assert completed.returncode == 0, \
                        f"exited with status {completed.returncode}: {completed.stderr[-1000:]}"
                    validate_hidden_result(target, primer, expected_mean, expected_std)
                except Exception as exc:
                    passed = False
                    errors.append(f"{' '.join(command)}: {exc}")
                    break
            if passed:
                return
        pytest.fail("No submitted script correctly processed replacement HDF5 assays. " + " | ".join(errors[-5:]))
    finally:
        with open(H5_PATH, "wb") as f:
            f.write(original_h5)
        with open(JSON_PATH, "wb") as f:
            f.write(original_json)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
