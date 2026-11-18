#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import sys

import pytest

BASE_DIR = "/home/user/pipeline_diag"
SCRIPT = os.path.join(BASE_DIR, "run_pipeline.py")
INPUT = os.path.join(BASE_DIR, "input.json")
EXPECTED = os.path.join(BASE_DIR, "expected.txt")


def flatten_reference(value):
    result = []
    for item in value:
        if isinstance(item, list):
            result.extend(flatten_reference(item))
        else:
            result.append(item)
    return result


def expected_output(data):
    values = flatten_reference(data)
    return f"SUM: {sum(values):.9f}"


def run_pipeline(input_path, timeout=5):
    try:
        return subprocess.run(
            ["python3", SCRIPT, input_path],
            cwd=BASE_DIR,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("run_pipeline.py timed out. The infinite loop or deadlock is not fully fixed.")


def test_hanging_syscall_txt():
    file_path = os.path.join(BASE_DIR, "hanging_syscall.txt")
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "read", (
        "hanging_syscall.txt must contain the exact syscall name 'read'; "
        f"found: {content!r}"
    )


def test_requested_output_and_diff_files():
    output_path = os.path.join(BASE_DIR, "output.txt")
    patch_path = os.path.join(BASE_DIR, "final_diff.patch")

    assert os.path.isfile(output_path), f"File {output_path} is missing."
    assert os.path.isfile(EXPECTED), f"File {EXPECTED} is missing."
    assert os.path.isfile(patch_path), f"File {patch_path} is missing."

    with open(output_path, "rb") as f:
        output_bytes = f.read()
    with open(EXPECTED, "rb") as f:
        expected_bytes = f.read()
    with open(patch_path, "rb") as f:
        patch_bytes = f.read()

    assert output_bytes.strip() == expected_bytes.strip(), "output.txt does not match expected.txt."
    assert os.path.getsize(patch_path) == 0, "final_diff.patch must be empty when the files match."

    actual_diff = subprocess.run(
        ["diff", "-u", EXPECTED, output_path], capture_output=True
    )
    assert actual_diff.returncode == 0, "The requested diff reports that output.txt differs from expected.txt."
    assert patch_bytes == actual_diff.stdout, "final_diff.patch is not the diff of expected.txt and output.txt."


def test_canonical_pipeline_and_artifacts_match_derived_answer():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    with open(INPUT, "r") as f:
        data = json.load(f)
    derived = expected_output(data)

    result = run_pipeline(INPUT)
    assert result.returncode == 0, (
        f"run_pipeline.py failed with return code {result.returncode}. Stderr: {result.stderr}"
    )
    assert result.stdout.strip() == derived, (
        f"run_pipeline.py produced incorrect output. Expected {derived!r}, got {result.stdout.strip()!r}"
    )

    with open(EXPECTED, "r") as f:
        assert f.read().strip() == derived, "expected.txt was altered or is inconsistent with input.json."
    with open(os.path.join(BASE_DIR, "output.txt"), "r") as f:
        assert f.read().strip() == derived, "output.txt is not the canonical pipeline output."


def test_pipeline_on_unseen_nested_inputs():
    rng = secrets.SystemRandom()
    random_values = [rng.randrange(1, 10**12) / 10**7 for _ in range(7)]
    cases = [
        [0.123456789123, [1000000.000000321, [2.000000000019]], [], 7.777777777777],
        [random_values[0], [random_values[1], [random_values[2], random_values[3]]],
         random_values[4], [[], random_values[5]], random_values[6]],
    ]

    for index, data in enumerate(cases):
        path = os.path.join(BASE_DIR, f".verifier_input_{os.getpid()}_{index}.json")
        try:
            with open(path, "w") as f:
                json.dump(data, f)
            result = run_pipeline(path)
            assert result.returncode == 0, (
                f"Pipeline failed on an unseen input: {result.stderr}"
            )
            assert result.stdout.strip() == expected_output(data), (
                "Pipeline does not correctly flatten and aggregate an unseen nested input."
            )
        finally:
            if os.path.exists(path):
                os.unlink(path)


def test_pipeline_uses_aggregator_double_protocol():
    aggregator = os.path.join(BASE_DIR, "aggregator")
    assert os.path.isfile(aggregator), "Compiled aggregator is missing."

    original = open(aggregator, "rb").read()
    original_mode = stat.S_IMODE(os.stat(aggregator).st_mode)
    token = secrets.token_hex(12)
    marker = f"/tmp/pipeline_protocol_{token}.json"
    probe_input = os.path.join(BASE_DIR, f".protocol_input_{token}.json")
    data = [1.000000000001, [2.123456789123, [3.987654321987]], 4.000000000007]

    wrapper = f'''#!/usr/bin/env python3
import json
import struct
import sys
marker = {marker!r}
count = int(sys.argv[1])
payload = sys.stdin.buffer.read()
record = {{"count": count, "length": len(payload)}}
if len(payload) != count * 8:
    with open(marker, "w") as f:
        json.dump(record, f)
    sys.exit(3)
values = list(struct.unpack("=" + "d" * count, payload))
record["values"] = values
with open(marker, "w") as f:
    json.dump(record, f)
print(f"SUM: {{sum(values):.9f}}")
'''

    try:
        with open(probe_input, "w") as f:
            json.dump(data, f)
        with open(aggregator, "w") as f:
            f.write(wrapper)
        os.chmod(aggregator, 0o755)

        result = run_pipeline(probe_input)
        assert result.returncode == 0, f"Pipeline failed during protocol probe: {result.stderr}"
        assert os.path.isfile(marker), "run_pipeline.py did not execute ./aggregator."
        with open(marker, "r") as f:
            record = json.load(f)

        values = flatten_reference(data)
        assert record["count"] == len(values), "Incorrect value count passed to aggregator."
        assert record["length"] == len(values) * 8, (
            "Aggregator input was not serialized as one 8-byte double per value."
        )
        assert record.get("values") == values, "Serialized double values were truncated or reordered."
        assert result.stdout.strip() == expected_output(data)
    finally:
        with open(aggregator, "wb") as f:
            f.write(original)
        os.chmod(aggregator, original_mode)
        for path in (marker, probe_input):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
