#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import io
import json
import os
import random
import subprocess
import pytest


def test_fastcsv_installed_and_fixed():
    try:
        import fastcsv
    except ImportError:
        pytest.fail("fastcsv is not installed in the environment.")

    try:
        import fastcsv._c_ext as c_ext
    except ImportError:
        pytest.fail("fastcsv is installed but the C-extension (_c_ext) is not available. The build configuration was not fixed correctly.")

    module_path = os.path.realpath(c_ext.__file__)
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        "fastcsv._c_ext is not a compiled extension module"

    assert getattr(fastcsv.parse_records, "__module__", None) == "fastcsv._c_ext", \
        "fastcsv is not using its C-extension parser"
    parsed = fastcsv.parse_records(b'7,utf-8,"first line\nsecond, line"\n')
    assert parsed == [(b"7", b"utf-8", b"first line\nsecond, line")], \
        "The installed fastcsv parser still mishandles embedded newlines"


def make_csv_row(row_id, encoding, payload):
    escaped = payload.replace(b'"', b'""')
    return str(row_id).encode("ascii") + b"," + encoding.encode("ascii") + b',"' + escaped + b'"\n'


def expected_object(row_id, encoding, payload):
    decoded = payload.decode(encoding, errors="replace")
    return {
        "id": row_id,
        "payload_length": len(decoded),
        "normalized_payload": decoded,
    }


def generate_fuzz_input(seed, num_rows):
    rng = random.Random(seed)
    encodings = ["utf-8", "iso-8859-1", "cp1252", "windows-1252"]
    out = io.BytesIO()
    expected = []

    for _ in range(num_rows):
        row_id = rng.randint(1, 100000)
        encoding = rng.choice(encodings)
        payload_len = rng.randint(10, 100)
        payload = bytearray(rng.getrandbits(8) for _ in range(payload_len))

        for _ in range(rng.randint(0, 4)):
            idx = rng.randint(0, payload_len - 1)
            payload[idx] = rng.choice([ord("\n"), ord("\r"), ord(","), ord('"')])

        payload = bytes(payload)
        out.write(make_csv_row(row_id, encoding, payload))
        expected.append(expected_object(row_id, encoding, payload))

    return out.getvalue(), expected


def run_and_check(csv_data, expected, label):
    agent_script = "/home/user/stream_etl.py"
    proc = subprocess.run(
        [agent_script],
        input=csv_data,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, \
        f"Agent script failed on {label} with return code {proc.returncode}.\nStderr: {proc.stderr.decode('utf-8', errors='replace')}"

    try:
        text = proc.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        pytest.fail(f"Output on {label} is not valid UTF-8: {exc}")

    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    assert len(lines) == len(expected), \
        f"Expected {len(expected)} JSON objects on {label}, got {len(lines)}"

    actual = []
    for index, line in enumerate(lines):
        assert line, f"Empty JSONL record at index {index} on {label}"
        try:
            obj = json.loads(line)
        except Exception as exc:
            pytest.fail(f"Invalid JSON at record {index} on {label}: {exc}")
        assert isinstance(obj, dict), f"Record {index} on {label} is not a JSON object"
        assert set(obj) == {"id", "payload_length", "normalized_payload"}, \
            f"Record {index} on {label} has incorrect keys"
        assert type(obj["id"]) is int, f"Record {index} has a non-integer id"
        assert type(obj["payload_length"]) is int, f"Record {index} has a non-integer payload_length"
        assert type(obj["normalized_payload"]) is str, f"Record {index} has a non-string normalized_payload"
        actual.append(obj)

    assert actual == expected, f"Incorrect transformed output on {label}"


def test_fuzz_equivalence():
    agent_script = "/home/user/stream_etl.py"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script at {agent_script} is not executable"

    deterministic_rows = [
        (1, "utf-8", b"plain text"),
        (2, "utf-8", "snowman: \u2603".encode("utf-8")),
        (3, "iso-8859-1", b"caf\xe9,with comma"),
        (4, "windows-1252", b"price \x8010"),
        (5, "utf-8", b"bad utf8: \xff\xfe"),
        (6, "utf-8", b"embedded\nnewline\rand \"quotes\", too"),
        (7, "utf-8", b""),
    ]
    deterministic_data = b"".join(make_csv_row(*row) for row in deterministic_rows)
    deterministic_expected = [expected_object(*row) for row in deterministic_rows]
    run_and_check(deterministic_data, deterministic_expected, "deterministic edge cases")

    for seed in range(50):
        num_rows = random.Random(100000 + seed).randint(10, 50)
        csv_data, expected = generate_fuzz_input(seed, num_rows)
        run_and_check(csv_data, expected, f"fuzz iteration {seed}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
