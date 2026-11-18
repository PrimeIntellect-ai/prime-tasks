#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_ORACLE="$(mktemp /tmp/sim_oracle.real.XXXXXX)"
ORACLE_LOG="$(mktemp /tmp/sim_oracle.calls.XXXXXX)"
cp /app/sim_oracle "$REAL_ORACLE"
chmod 755 "$REAL_ORACLE"

cleanup() {
    cp "$REAL_ORACLE" /app/sim_oracle 2>/dev/null || true
    chmod 755 /app/sim_oracle 2>/dev/null || true
    rm -f "$REAL_ORACLE" "$ORACLE_LOG"
}
trap cleanup EXIT

cat > /app/sim_oracle <<EOF
#!/bin/bash
printf '%s\t%s\n' "\$1" "\$2" >> "$ORACLE_LOG"
exec "$REAL_ORACLE" "\$@"
EOF
chmod 755 /app/sim_oracle

export REAL_ORACLE ORACLE_LOG

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import uuid

import pytest
from scipy.stats import ttest_ind

EXECUTABLE = "/home/user/filter_data"
SOURCE = "/home/user/filter_data.cpp"
REFERENCE = "/home/user/reference.json"
REAL_ORACLE = os.environ["REAL_ORACLE"]
ORACLE_LOG = os.environ["ORACLE_LOG"]


def oracle_score(path):
    result = subprocess.run(
        [REAL_ORACLE, path, REFERENCE], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    match = re.search(r"Similarity:\s*([-+0-9.eE]+)", result.stdout)
    assert match, f"Could not parse oracle output: {result.stdout!r}"
    return float(match.group(1))


def corpus_scores(directory):
    return [oracle_score(os.path.join(directory, name))
            for name in os.listdir(directory)
            if os.path.isfile(os.path.join(directory, name))]


CLEAN_SAMPLE_SCORES = corpus_scores("/home/user/sample_clean")
EVIL_SAMPLE_SCORES = corpus_scores("/home/user/sample_evil")
assert CLEAN_SAMPLE_SCORES and EVIL_SAMPLE_SCORES
assert min(CLEAN_SAMPLE_SCORES) > max(EVIL_SAMPLE_SCORES), "Calibration samples are not separable"
_TTEST = ttest_ind(CLEAN_SAMPLE_SCORES, EVIL_SAMPLE_SCORES, equal_var=False)
assert _TTEST.pvalue < 0.001 and sum(CLEAN_SAMPLE_SCORES) / len(CLEAN_SAMPLE_SCORES) > sum(EVIL_SAMPLE_SCORES) / len(EVIL_SAMPLE_SCORES)
THRESHOLD = (min(CLEAN_SAMPLE_SCORES) + max(EVIL_SAMPLE_SCORES)) / 2.0


def test_filter_data_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_cpp_source_exists_and_compiles():
    assert os.path.exists(SOURCE), f"C++ source {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", "/tmp/filter_data_rebuilt"],
        capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"C++ source failed to compile:\n{result.stderr}"
    assert os.access("/tmp/filter_data_rebuilt", os.X_OK)


def read_calls():
    calls = []
    if not os.path.exists(ORACLE_LOG):
        return calls
    with open(ORACLE_LOG, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t", 1)
            if len(parts) == 2:
                calls.append(tuple(parts))
    return calls


def assert_every_input_was_compared(input_dir):
    calls = read_calls()
    for name in os.listdir(input_dir):
        path = os.path.join(input_dir, name)
        if not os.path.isfile(path):
            continue
        absolute = os.path.abspath(path)
        assert any(
            {os.path.abspath(a), os.path.abspath(b)} == {absolute, os.path.abspath(REFERENCE)}
            for a, b in calls
        ), f"The similarity oracle was not invoked for input file {name}"


def run_and_check(executable, input_dir, output_dir, expected_names, timeout):
    open(ORACLE_LOG, "w").close()
    result = subprocess.run(
        [executable, input_dir, output_dir], capture_output=True, text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Executable failed with return code {result.returncode}.\nStderr: {result.stderr}"
    )
    output_names = set(os.listdir(output_dir))
    assert output_names == expected_names, (
        f"Expected exactly {len(expected_names)} preserved files, got {len(output_names)}; "
        f"missing={list(expected_names - output_names)[:5]}, "
        f"unexpected={list(output_names - expected_names)[:5]}"
    )
    for name in expected_names:
        source = os.path.join(input_dir, name)
        destination = os.path.join(output_dir, name)
        assert os.path.isfile(destination), f"Output {name} is not a regular file"
        with open(source, "rb") as left, open(destination, "rb") as right:
            assert left.read() == right.read(), f"Output file {name} was modified"
    assert_every_input_was_compared(input_dir)


def test_filter_data_correctness():
    clean_dir = "/verify/clean"
    evil_dir = "/verify/evil"

    assert os.path.exists(clean_dir), f"Missing clean corpus dir: {clean_dir}"
    assert os.path.exists(evil_dir), f"Missing evil corpus dir: {evil_dir}"

    clean_files = set(os.listdir(clean_dir))
    evil_files = set(os.listdir(evil_dir))

    assert len(clean_files) > 0, "Clean corpus is empty."
    assert len(evil_files) > 0, "Evil corpus is empty."

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        for name in clean_files:
            shutil.copy(os.path.join(clean_dir, name), os.path.join(input_dir, name))
        for name in evil_files:
            shutil.copy(os.path.join(evil_dir, name), os.path.join(input_dir, name))

        try:
            run_and_check(EXECUTABLE, input_dir, output_dir, clean_files, 60)
        except subprocess.TimeoutExpired:
            pytest.fail("Execution of /home/user/filter_data timed out after 60 seconds.")


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[int((len(ordered) - 1) * fraction)]


def write_profile_for_score(path, score, slot, sign):
    distance = (1.0 / score) - 1.0
    features = [0.0] * 10
    features[slot] = sign * distance
    with open(path, "w") as handle:
        json.dump({"features": features}, handle)


def test_randomized_unlabelled_content_and_rebuilt_cpp():
    # Scores are chosen well inside the two calibration distributions, so every
    # threshold separating the supplied calibration samples gives the same answer.
    clean_low = min(CLEAN_SAMPLE_SCORES)
    clean_high = percentile(CLEAN_SAMPLE_SCORES, 0.65)
    evil_low = percentile(EVIL_SAMPLE_SCORES, 0.35)
    evil_high = max(EVIL_SAMPLE_SCORES)
    assert clean_low > evil_high

    with tempfile.TemporaryDirectory() as input_dir:
        expected = set()
        for index in range(48):
            is_clean = index % 2 == 0
            fraction = ((index * 37) % 97 + 1) / 98.0
            if is_clean:
                score = clean_low + (clean_high - clean_low) * fraction
            else:
                score = evil_low + (evil_high - evil_low) * fraction
            name = f"{uuid.uuid4().hex}.json"
            path = os.path.join(input_dir, name)
            write_profile_for_score(path, score, index % 10, -1 if index % 3 else 1)
            measured = oracle_score(path)
            assert abs(measured - THRESHOLD) > 1e-5
            if measured > THRESHOLD:
                expected.add(name)
            assert (measured > THRESHOLD) == is_clean

        for executable in (EXECUTABLE, "/tmp/filter_data_rebuilt"):
            with tempfile.TemporaryDirectory() as output_dir:
                try:
                    run_and_check(executable, input_dir, output_dir, expected, 30)
                except subprocess.TimeoutExpired:
                    pytest.fail(f"Execution of {executable} timed out on randomized inputs")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
