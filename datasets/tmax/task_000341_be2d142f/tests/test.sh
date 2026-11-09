#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import uuid

import pytest

SCRIPT_PATH = "/home/user/filter.py"
BASELINE = [float(i) for i in range(10)]


def run_filter(path, env=None):
    return subprocess.run(
        ["python3", SCRIPT_PATH, str(path)],
        capture_output=True,
        timeout=10,
        env=env,
    )


def write_json(path, readings, encoding):
    payload = json.dumps({"sensor_readings": readings})
    with open(path, "wb") as f:
        f.write(payload.encode(encoding))


def expected_distance(seq1, seq2=BASELINE):
    return sum(abs(a - b) for a, b in zip(seq1, seq2)) + abs(len(seq1) - len(seq2)) * 10.0


def test_filter_script_exists():
    script_path = "/home/user/filter.py"
    assert os.path.isfile(script_path), f"Missing filter script at {script_path}"


def test_adversarial_corpus():
    script_path = "/home/user/filter.py"
    clean_dir = "/app/data/clean"
    evil_dir = "/app/data/evil"

    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for f in clean_files:
        result = subprocess.run(["python3", script_path, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run(["python3", script_path, f], capture_output=True)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(f))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_vendored_package_installed():
    # Verify the vendored package can be imported and works as expected
    try:
        import ts_distance
    except ImportError:
        pytest.fail("The vendored package 'ts_distance' is not installed or importable.")

    result = ts_distance.compute_dtw([1.0, 2.0], [1.0, 2.0])
    assert result == 0.0, "The compute_dtw function did not return the expected result."


def test_generated_inputs_at_unlabelled_paths(tmp_path):
    rng = random.SystemRandom()
    cases = []

    # Random affine sequences remain affine after strict interpolation and are close
    # enough to be accepted. Both supported encodings are exercised without a BOM.
    for i in range(8):
        offset = rng.uniform(-0.35, 0.35)
        slope = rng.uniform(-0.04, 0.04)
        completed = [float(j) + offset + slope * j for j in range(10)]
        encoded = list(completed)
        start = rng.randint(1, 6)
        width = rng.randint(1, min(3, 8 - start))
        for j in range(start, start + width):
            encoded[j] = None
        assert expected_distance(completed) < 15.0
        cases.append((encoded, "utf-8" if i % 2 == 0 else "utf-16-le", 0))

    # Random far-away sequences must be rejected in both encodings.
    for i in range(6):
        shift = rng.uniform(20.0, 60.0)
        values = [float(j) + shift for j in range(10)]
        assert expected_distance(values) >= 15.0
        cases.append((values, "utf-8" if i % 2 == 0 else "utf-16-le", 1))

    # Exercise the strict threshold rather than merely obviously distant values.
    below = list(BASELINE)
    below[rng.randrange(10)] += 14.9
    at_limit = list(BASELINE)
    at_limit[rng.randrange(10)] += 15.0
    cases.extend([
        (below, "utf-8", 0),
        (at_limit, "utf-16-le", 1),
        ([], "utf-8", 1),
    ])

    rng.shuffle(cases)
    for readings, encoding, expected_code in cases:
        path = tmp_path / (uuid.uuid4().hex + ".bin")
        write_json(path, readings, encoding)
        result = run_filter(path)
        assert result.returncode == expected_code, (
            f"Unexpected exit code for generated {encoding} input: "
            f"expected {expected_code}, got {result.returncode}; "
            f"stderr={result.stderr!r}"
        )

    invalid_payloads = [
        b"not json at all",
        json.dumps({"other_key": [float(i) for i in range(10)]}).encode("utf-8"),
        json.dumps({"sensor_readings": "not a list"}).encode("utf-8"),
        b"\xff\xfe\xff\xffbroken",
    ]
    for payload in invalid_payloads:
        path = tmp_path / (uuid.uuid4().hex + ".bin")
        path.write_bytes(payload)
        assert run_filter(path).returncode == 1


def test_filter_calls_dtw_with_interpolated_values(tmp_path):
    probe_root = tmp_path / uuid.uuid4().hex
    package_dir = probe_root / "ts_distance"
    package_dir.mkdir(parents=True)
    log_path = tmp_path / (uuid.uuid4().hex + ".log")
    (package_dir / "__init__.py").write_text(
        "import json, os\n"
        "def compute_dtw(seq1, seq2):\n"
        "    with open(os.environ['DTW_PROBE_LOG'], 'a') as f:\n"
        "        f.write(json.dumps([seq1, seq2]) + '\\n')\n"
        "    return sum(abs(a-b) for a,b in zip(seq1,seq2)) + abs(len(seq1)-len(seq2))*10.0\n"
    )

    rng = random.SystemRandom()
    offset = rng.uniform(-0.25, 0.25)
    slope = rng.uniform(0.02, 0.08)
    completed = [float(i) + offset + slope * i for i in range(10)]
    readings = list(completed)
    readings[3:6] = [None, None, None]
    path = tmp_path / (uuid.uuid4().hex + ".dat")
    write_json(path, readings, "utf-16-le")

    env = os.environ.copy()
    env["PYTHONPATH"] = str(probe_root)
    env["DTW_PROBE_LOG"] = str(log_path)
    result = run_filter(path, env=env)
    assert result.returncode == 0, result.stderr
    assert log_path.is_file(), "filter did not call ts_distance.compute_dtw"

    calls = [json.loads(line) for line in log_path.read_text().splitlines() if line]
    assert calls, "filter did not record a DTW call"
    seq1, seq2 = calls[-1]
    assert seq1 == pytest.approx(completed)
    assert seq2 == pytest.approx(BASELINE)


def test_malicious_empty_hash_is_rejected_even_if_dtw_would_accept(tmp_path):
    probe_root = tmp_path / uuid.uuid4().hex
    package_dir = probe_root / "ts_distance"
    package_dir.mkdir(parents=True)
    (package_dir / "__init__.py").write_text(
        "def compute_dtw(seq1, seq2):\n"
        "    return 0.0\n"
    )

    path = tmp_path / (uuid.uuid4().hex + ".dat")
    write_json(path, [], "utf-8")
    env = os.environ.copy()
    env["PYTHONPATH"] = str(probe_root)
    assert run_filter(path, env=env).returncode == 1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
