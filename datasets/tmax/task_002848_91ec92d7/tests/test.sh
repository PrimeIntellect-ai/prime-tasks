#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import stat
import subprocess
import secrets
import pytest


def compute_expected(fasta_content):
    sequences = {}
    current_id = None
    for line in fasta_content.strip().split('\n'):
        line = line.strip()
        if not line:
            continue
        if line.startswith('>'):
            current_id = line[1:].strip()
            sequences[current_id] = ""
        elif current_id:
            sequences[current_id] += line

    result = {}
    for seq_id, seq in sequences.items():
        raw = []
        for i, char in enumerate(seq):
            raw.append((ord(char) * 10) + (math.sin(i) * 5.0))

        filtered = []
        n = len(raw)
        for i in range(n):
            val_prev = raw[i-1] if i - 1 >= 0 else 0.0
            val_curr = raw[i]
            val_next = raw[i+1] if i + 1 < n else 0.0
            filtered.append(round((val_prev + val_curr + val_next) / 3.0, 2))
        result[seq_id] = filtered
    return result


def test_ml_env_directory_exists():
    path = "/home/user/ml_env"
    assert os.path.isdir(path), f"Environment directory {path} does not exist. You must create it."


def test_training_data_json():
    input_fasta_path = "/home/user/data/input.fasta"
    output_json_path = "/home/user/output/training_data.json"

    assert os.path.isfile(input_fasta_path), f"Input FASTA {input_fasta_path} is missing."
    assert os.path.isfile(output_json_path), f"Output JSON {output_json_path} was not created."

    with open(input_fasta_path, 'r') as f:
        fasta_content = f.read()

    expected_data = compute_expected(fasta_content)

    try:
        with open(output_json_path, 'r') as f:
            actual_data = json.load(f)
    except Exception as e:
        pytest.fail(f"Could not parse {output_json_path} as JSON: {e}")

    for key, expected_arr in expected_data.items():
        assert key in actual_data, f"Sequence ID '{key}' missing in output JSON."
        actual_arr = actual_data[key]
        assert len(expected_arr) == len(actual_arr), f"Length mismatch for sequence '{key}'. Expected {len(expected_arr)}, got {len(actual_arr)}."

        for i, (exp_val, act_val) in enumerate(zip(expected_arr, actual_arr)):
            assert math.isclose(exp_val, act_val, abs_tol=0.01), \
                f"Value mismatch in sequence '{key}' at index {i}: expected {exp_val}, got {act_val}."


def test_test_pipeline_script():
    script_path = "/home/user/test_pipeline.sh"
    test_fasta_path = "/home/user/data/test.fasta"
    baseline_path = "/home/user/data/expected_test.json"
    output_path = "/home/user/output/training_data.json"

    assert os.path.isfile(script_path), f"Regression test script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    original_test = open(test_fasta_path, "rb").read()
    original_baseline = open(baseline_path, "rb").read()
    output_existed = os.path.isfile(output_path)
    original_output = open(output_path, "rb").read() if output_existed else None

    try:
        try:
            result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
        except Exception as e:
            pytest.fail(f"Failed to execute {script_path}: {e}")

        assert result.returncode == 0, f"Regression test script failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

        alphabet = "ACDEFGHIKLMNPQRSTVWY"
        seq1 = ''.join(secrets.choice(alphabet) for _ in range(7))
        seq2 = ''.join(secrets.choice(alphabet) for _ in range(11))
        id1 = "varied_" + secrets.token_hex(6)
        id2 = "varied_" + secrets.token_hex(6)
        varied_fasta = f">{id1}\n{seq1[:3]}\n{seq1[3:]}\n>{id2}\n{seq2[:5]}\n{seq2[5:]}\n"
        varied_expected = compute_expected(varied_fasta)

        with open(test_fasta_path, "w") as f:
            f.write(varied_fasta)
        with open(baseline_path, "w") as f:
            json.dump(varied_expected, f, indent=2)
            f.write("\n")
        if os.path.exists(output_path):
            os.remove(output_path)

        result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, \
            f"Regression test did not accept a correct varied-input baseline.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        assert os.path.isfile(output_path), "Running the regression test did not generate training_data.json."
        try:
            with open(output_path, "r") as f:
                varied_actual = json.load(f)
        except Exception as e:
            pytest.fail(f"Pipeline output for varied input is not valid JSON: {e}")
        assert varied_actual == varied_expected, \
            f"Pipeline did not compute the required result for varied FASTA input. Expected {varied_expected}, got {varied_actual}."

        with open(baseline_path, "w") as f:
            json.dump({"intentionally_wrong": [123.45]}, f, indent=2)
            f.write("\n")
        if os.path.exists(output_path):
            os.remove(output_path)

        result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
        assert result.returncode != 0, \
            "Regression test returned success even though expected_test.json was deliberately incorrect."
        assert os.path.isfile(output_path), \
            "Regression test did not run the pipeline before checking the deliberately incorrect baseline."
        try:
            with open(output_path, "r") as f:
                mismatch_run_actual = json.load(f)
        except Exception as e:
            pytest.fail(f"Pipeline output from mismatch test is not valid JSON: {e}")
        assert mismatch_run_actual == varied_expected, \
            "The regression script appears to copy or trust expected_test.json instead of independently generating pipeline output."
    finally:
        with open(test_fasta_path, "wb") as f:
            f.write(original_test)
        with open(baseline_path, "wb") as f:
            f.write(original_baseline)
        if output_existed:
            with open(output_path, "wb") as f:
                f.write(original_output)
        elif os.path.exists(output_path):
            os.remove(output_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
