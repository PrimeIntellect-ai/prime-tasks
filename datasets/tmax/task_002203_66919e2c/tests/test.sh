#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import random
import subprocess
import sys
import tempfile

import pytest

SCRIPT_PATH = "/home/user/process_series.py"
VENDORED_ROOT = "/app/vendored/jsonlines-3.1.0"
VENDORED_SOURCE = "/app/vendored/jsonlines-3.1.0/jsonlines/jsonlines.py"


def has_pii(obj):
    if isinstance(obj, dict):
        if "ssn" in obj or "email" in obj:
            return True
        return any(has_pii(value) for value in obj.values())
    if isinstance(obj, list):
        return any(has_pii(value) for value in obj)
    return False


def expected_processing(lines):
    valid_records = []
    for line in lines:
        if not line.strip():
            continue
        record = json.loads(line)
        if not has_pii(record):
            valid_records.append(record)

    result = []
    prev_record = None
    for record in valid_records:
        if prev_record is not None:
            if record["sensor_payload"] == prev_record["sensor_payload"]:
                continue

            gap = record["timestamp"] - prev_record["timestamp"]
            if gap > 1:
                start_val = prev_record["sensor_payload"].get("value", 0.0)
                end_val = record["sensor_payload"].get("value", 0.0)
                for i in range(1, gap):
                    new_record = {
                        "timestamp": prev_record["timestamp"] + i,
                        "sensor_payload": copy.deepcopy(prev_record["sensor_payload"]),
                    }
                    new_record["sensor_payload"]["value"] = (
                        start_val + (end_val - start_val) * i / gap
                    )
                    result.append(new_record)
        result.append(record)
        prev_record = record
    return result


def make_tracking_site(directory):
    sitecustomize = os.path.join(directory, "sitecustomize.py")
    with open(sitecustomize, "w", encoding="utf-8") as handle:
        handle.write(r'''
import os
try:
    import jsonlines

    def _wrap_jsonlines_method(function):
        def wrapped(*args, **kwargs):
            marker = os.environ.get("TRACK_JSONLINES_MARKER")
            if marker:
                with open(marker, "a", encoding="utf-8") as stream:
                    stream.write("used\n")
            return function(*args, **kwargs)
        return wrapped

    for _name in ("read", "iter"):
        if hasattr(jsonlines.Reader, _name):
            setattr(jsonlines.Reader, _name,
                    _wrap_jsonlines_method(getattr(jsonlines.Reader, _name)))
except Exception:
    pass
''')


def run_student_script(input_path, output_path):
    assert os.path.isfile(SCRIPT_PATH), f"Student script missing at {SCRIPT_PATH}"

    with tempfile.TemporaryDirectory() as tracking_dir:
        make_tracking_site(tracking_dir)
        marker = os.path.join(tracking_dir, "jsonlines-used")
        env = os.environ.copy()
        env["PYTHONPATH"] = os.pathsep.join(
            [tracking_dir, VENDORED_ROOT, env.get("PYTHONPATH", "")]
        )
        env["TRACK_JSONLINES_MARKER"] = marker

        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, input_path, output_path],
                capture_output=True,
                text=True,
                env=env,
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            return False, "timed out"

        if result.returncode != 0:
            return False, result.stderr
        if not os.path.isfile(marker) or os.path.getsize(marker) == 0:
            return False, "vendored jsonlines Reader was not used"
        return True, ""


def read_output(path):
    assert os.path.isfile(path), "no output file"
    records = []
    with open(path, "r", encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            if line.strip():
                try:
                    records.append(json.loads(line))
                except Exception as exc:
                    pytest.fail(f"invalid JSON on output line {number}: {exc}")
    return records


def test_corpora_processing():
    clean_corpus = "/app/corpora/clean"
    evil_corpus = "/app/corpora/evil"

    clean_files = [f for f in os.listdir(clean_corpus) if f.endswith(".jsonl")]
    evil_files = [f for f in os.listdir(evil_corpus) if f.endswith(".jsonl")]

    failed_clean = []
    failed_evil = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(clean_corpus, filename)
            output_path = os.path.join(tmpdir, f"out_clean_{filename}")
            with open(input_path, "r", encoding="utf-8") as infile:
                expected = expected_processing(infile.readlines())

            success, error = run_student_script(input_path, output_path)
            if not success:
                failed_clean.append(f"{filename} (crashed: {error.strip()})")
                continue
            try:
                actual = read_output(output_path)
            except AssertionError as exc:
                failed_clean.append(f"{filename} ({exc})")
                continue
            if actual != expected:
                failed_clean.append(filename)

        for filename in evil_files:
            input_path = os.path.join(evil_corpus, filename)
            output_path = os.path.join(tmpdir, f"out_evil_{filename}")
            with open(input_path, "r", encoding="utf-8") as infile:
                expected = expected_processing(infile.readlines())

            success, error = run_student_script(input_path, output_path)
            if not success:
                failed_evil.append(f"{filename} (crashed: {error.strip()})")
                continue
            try:
                actual = read_output(output_path)
            except AssertionError as exc:
                failed_evil.append(f"{filename} ({exc})")
                continue
            if actual != expected:
                failed_evil.append(filename)

    errors = []
    if failed_clean:
        errors.append(
            f"{len(failed_clean)} of {len(clean_files)} clean modified/failed: "
            + ", ".join(failed_clean)
        )
    if failed_evil:
        errors.append(
            f"{len(failed_evil)} of {len(evil_files)} evil bypassed/failed: "
            + ", ".join(failed_evil)
        )
    if errors:
        pytest.fail(" | ".join(errors))


def randomized_records(rng):
    base = rng.randint(1000, 50000)
    gap_one = rng.randint(4, 8)
    gap_two = rng.randint(3, 7)
    value_a = rng.uniform(-40.0, 20.0)
    value_b = rng.uniform(30.0, 90.0)
    value_c = rng.uniform(-10.0, 110.0)

    payload_a = {
        "value": value_a,
        "unit": "°C",
        "node": {"rack": rng.randint(1, 20), "labels": ["north", {"ok": True}]},
    }
    payload_b = {
        "value": value_b,
        "unit": "°C",
        "node": {"rack": rng.randint(21, 40), "labels": ["south", {"ok": False}]},
    }
    payload_c = {
        "value": value_c,
        "unit": "°C",
        "node": {"rack": rng.randint(41, 60), "labels": ["west", {"ok": True}]},
    }

    second_time = base + gap_one
    third_time = second_time + gap_two
    records = [
        {"timestamp": base, "sensor_payload": payload_a},
        {"timestamp": base + 1, "sensor_payload": copy.deepcopy(payload_a)},
        {
            "timestamp": base + 2,
            "sensor_payload": {
                "value": rng.uniform(100, 200),
                "metadata": [{"safe": 1}, {"deep": {"email": "hidden@example.test"}}],
            },
        },
        {"timestamp": second_time, "sensor_payload": payload_b},
        {"timestamp": second_time + 1, "sensor_payload": copy.deepcopy(payload_b)},
        {
            "timestamp": second_time + 2,
            "sensor_payload": {"value": rng.uniform(200, 300), "unit": "°C"},
            "envelope": [{"nested": {"ssn": "000-00-0000"}}],
        },
        {"timestamp": third_time, "sensor_payload": payload_c},
    ]

    timestamp = third_time
    for index in range(12):
        timestamp += 1
        records.append(
            {
                "timestamp": timestamp,
                "sensor_payload": {
                    "value": value_c + index + 1,
                    "unit": "°C",
                    "node": {"sequence": index, "tags": ["tail", index]},
                },
            }
        )
    return records


def test_randomized_general_pipeline_and_real_unicode_escape():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as tmpdir:
        for case_number in range(5):
            records = randomized_records(rng)
            input_path = os.path.join(tmpdir, f"input_{rng.getrandbits(64):016x}.jsonl")
            output_path = os.path.join(tmpdir, f"output_{rng.getrandbits(64):016x}.jsonl")

            with open(input_path, "w", encoding="utf-8", newline="\n") as stream:
                stream.write("\n")
                for record in records:
                    stream.write(json.dumps(record, ensure_ascii=True, separators=(",", ":")))
                    stream.write("\n")

            with open(input_path, "rb") as stream:
                raw = stream.read()
            assert (chr(92) + "u00b0").encode("ascii") in raw
            assert "°".encode("utf-8") not in raw

            with open(input_path, "r", encoding="utf-8") as stream:
                expected = expected_processing(stream)

            success, error = run_student_script(input_path, output_path)
            assert success, f"random case {case_number} failed: {error}"
            actual = read_output(output_path)
            assert actual == expected
            assert all(not has_pii(record) for record in actual)


def test_vendored_library_fixed():
    with open(VENDORED_SOURCE, "r", encoding="utf-8") as stream:
        content = stream.read()

    lines = content.split("\n")
    for line in lines:
        if "Unicode escapes strictly forbidden" in line:
            assert line.strip().startswith("#"), (
                "The malicious perturbation in jsonlines.py is not commented out or removed."
            )

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "unicode.jsonl")
        with open(input_path, "w", encoding="ascii") as stream:
            stream.write('{"unit":"' + chr(92) + 'u00b0C","nested":{"name":"' + chr(92) + 'u03bb"}}\n')

        code = r'''
import jsonlines
import os
import sys
root = os.path.realpath(sys.argv[2]) + os.sep
assert os.path.realpath(jsonlines.__file__).startswith(root)
with jsonlines.open(sys.argv[1], mode="r") as reader:
    records = list(reader)
assert records == [{"unit": "°C", "nested": {"name": "λ"}}]
'''
        env = os.environ.copy()
        env["PYTHONPATH"] = VENDORED_ROOT
        result = subprocess.run(
            [sys.executable, "-c", code, input_path, VENDORED_ROOT],
            capture_output=True,
            text=True,
            env=env,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr or result.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
