#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import stat
import subprocess
import tempfile

SOURCE = '/home/user/log_analyzer.cpp'
BINARY = '/home/user/log_analyzer'
SYSTEM_LOG = '/home/user/system.log'
FINAL_OUTPUT = '/home/user/analysis_results.json'


def load_json(path):
    assert os.path.isfile(path), f"The output file {path} is missing."
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"The file {path} is not valid JSON: {exc}")


def expected_from_log(path):
    values = []
    decoded_bytes = 0
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            assert len(parts) == 3
            bytes.fromhex(parts[1])
            decoded_bytes += len(parts[1]) // 2
            values.append(float(parts[2]))

    mean = math.fsum(values) / len(values)
    variance = math.fsum((x - mean) ** 2 for x in values) / len(values)
    return len(values), decoded_bytes, variance


def assert_results(data, expected_entries, expected_bytes, expected_variance):
    assert "total_entries" in data, "The JSON output is missing the 'total_entries' field."
    assert "decoded_bytes_count" in data, "The JSON output is missing the 'decoded_bytes_count' field."
    assert "variance" in data, "The JSON output is missing the 'variance' field."
    assert data["total_entries"] == expected_entries, (
        f"Expected 'total_entries' to be {expected_entries}, but got {data['total_entries']}."
    )
    assert data["decoded_bytes_count"] == expected_bytes, (
        f"Expected 'decoded_bytes_count' to be {expected_bytes}, but got {data['decoded_bytes_count']}."
    )
    actual_variance = float(data["variance"])
    assert math.isfinite(actual_variance)
    assert math.isclose(actual_variance, expected_variance, rel_tol=0.0, abs_tol=2e-10), (
        f"Expected 'variance' to be close to {expected_variance}, but got {actual_variance}."
    )


def run_analyzer(binary, input_path, output_path):
    subprocess.run([binary, input_path, output_path], check=True, timeout=15)
    return load_json(output_path)


def test_analysis_results_content_and_provenance():
    final_data = load_json(FINAL_OUTPUT)
    expected_entries, expected_bytes, expected_variance = expected_from_log(SYSTEM_LOG)

    # Preserve the original checks, with the corrected decoded byte count.
    assert expected_entries == 1000
    assert expected_bytes == 15890
    assert math.isclose(expected_variance, 0.00000825, rel_tol=0.0, abs_tol=1e-10)
    assert_results(final_data, 1000, 15890, 0.00000825)

    assert os.path.isfile(BINARY), f"The compiled tool {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"The compiled tool {BINARY} is not executable."
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{BINARY} is not a compiled ELF executable."

    with tempfile.TemporaryDirectory() as td:
        rerun_path = os.path.join(td, 'system-results.json')
        rerun_data = run_analyzer(BINARY, SYSTEM_LOG, rerun_path)
        assert_results(rerun_data, expected_entries, expected_bytes, expected_variance)
        assert rerun_data == final_data, (
            "analysis_results.json is not the exact JSON produced by the submitted compiled tool."
        )


def test_fixed_source_and_binary_on_independent_log():
    assert os.path.isfile(SOURCE), f"The source file {SOURCE} is missing."

    with tempfile.TemporaryDirectory() as td:
        test_log = os.path.join(td, 'independent.log')
        submitted_output = os.path.join(td, 'submitted.json')
        rebuilt_output = os.path.join(td, 'rebuilt.json')
        rebuilt_binary = os.path.join(td, 'rebuilt_analyzer')

        with open(test_log, 'w') as f:
            for i in range(53):
                payload = f"Probe_{i}_Az".encode('utf-8')
                encoded = payload.hex()
                if i % 3 == 0:
                    encoded = encoded.upper()
                elif i % 3 == 2:
                    encoded = ''.join(c.upper() if j % 2 else c.lower()
                                      for j, c in enumerate(encoded))
                response = 1000000.0 + (i % 11) * 0.001
                f.write(f"{1700000000 + i} {encoded} {response:.4f}\n")

        expected = expected_from_log(test_log)
        submitted_data = run_analyzer(BINARY, test_log, submitted_output)
        assert_results(submitted_data, *expected)

        subprocess.run(
            ['g++', '-O2', '-std=c++17', '-o', rebuilt_binary, SOURCE],
            check=True,
            timeout=30,
        )
        rebuilt_data = run_analyzer(rebuilt_binary, test_log, rebuilt_output)
        assert_results(rebuilt_data, *expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
