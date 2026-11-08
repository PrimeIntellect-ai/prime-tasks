#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import secrets
import subprocess
import tempfile
import time
import urllib.request

import pytest
import redis

EXE = "/home/user/csv_filter"
SOURCE = "/home/user/csv_filter.cpp"
LOG = "/home/user/experiment_log.txt"
REBUILT = None


def fetch_threshold():
    response = urllib.request.urlopen("http://127.0.0.1:5000/threshold", timeout=5)
    body = response.read().decode("utf-8")
    return response.status, body, json.loads(body)


def redis_connection():
    with open("/app/services/flask_service/config.json", encoding="utf-8") as f:
        config = json.load(f)
    return redis.Redis(
        host=config["redis_host"],
        port=int(config["redis_port"]),
        decode_responses=True,
    )


def wait_for_threshold(expected):
    last = None
    for _ in range(30):
        try:
            status, body, data = fetch_threshold()
            last = (status, body)
            if status == 200 and isinstance(data, dict) and math.isclose(
                float(data.get("threshold")), expected, rel_tol=0, abs_tol=1e-9
            ):
                return
        except Exception as exc:
            last = repr(exc)
        time.sleep(0.1)
    pytest.fail(f"Flask endpoint did not expose Redis threshold {expected}; last response: {last}")


def test_services_up_and_configured():
    """The endpoint must return 0.85 and actually read the configured Redis key."""
    try:
        status, body, data = fetch_threshold()
        assert "0.85" in body, f"Expected threshold 0.85 in response, got: {body}"
        assert status == 200
        assert isinstance(data, dict) and set(data) == {"threshold"}
        assert math.isclose(float(data["threshold"]), 0.85, rel_tol=0, abs_tol=1e-9)

        client = redis_connection()
        assert client.ping(), "Configured Redis instance is not reachable"
        assert math.isclose(float(client.get("threshold")), 0.85, rel_tol=0, abs_tol=1e-9)

        probe = 0.43217
        client.set("threshold", str(probe))
        wait_for_threshold(probe)
        client.set("threshold", "0.85")
        wait_for_threshold(0.85)
    except Exception as exc:
        try:
            redis_connection().set("threshold", "0.85")
        except Exception:
            pass
        pytest.fail(f"Failed to verify Redis-backed Flask threshold service: {exc}")


def test_executable_exists():
    """The requested artifact and C++ source must exist, and the artifact must be native."""
    assert os.path.isfile(EXE), f"Executable not found at {EXE}"
    assert os.access(EXE, os.X_OK), f"File at {EXE} is not executable"
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "csv_filter must be a compiled native executable"
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, "C++ source is empty"


def test_cpp_source_builds(tmp_path):
    """Rebuild the submitted C++ source so behavior cannot be supplied only by a script."""
    global REBUILT
    rebuilt = tmp_path / "csv_filter_rebuilt"
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", str(rebuilt), "-lcurl"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"csv_filter.cpp did not compile:\n{result.stderr}"
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)
    REBUILT = str(rebuilt)


def test_adversarial_corpus():
    """Retain classification checks over every supplied corpus file."""
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))

    assert len(evil_files) > 0, f"No CSV files found in {evil_dir}"
    assert len(clean_files) > 0, f"No CSV files found in {clean_dir}"

    evil_bypassed = []
    clean_modified = []
    for file_path in evil_files:
        result = subprocess.run([EXE, file_path], capture_output=True, timeout=15)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(file_path))
    for file_path in clean_files:
        result = subprocess.run([EXE, file_path], capture_output=True, timeout=15)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(file_path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def pearson(xs, ys):
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    dx = [x - mx for x in xs]
    dy = [y - my for y in ys]
    return sum(x * y for x, y in zip(dx, dy)) / math.sqrt(
        sum(x * x for x in dx) * sum(y * y for y in dy)
    )


def make_case(path, rng, threshold, should_be_evil, negative):
    for _ in range(100):
        target = min(0.98, threshold + 0.18) if should_be_evil else max(0.03, threshold - 0.18)
        if negative:
            target = -target
        xs = [rng.gauss(0, 1) for _ in range(180)]
        noise = [rng.gauss(0, 1) for _ in xs]
        scale = math.sqrt(max(0.0001, 1 - target * target))
        ys = [target * x + scale * n for x, n in zip(xs, noise)]
        actual = pearson(xs, ys)
        expected = abs(actual) > threshold
        if expected == should_be_evil and abs(abs(actual) - threshold) > 0.08:
            with open(path, "w", encoding="utf-8") as f:
                f.write("id,val_X,val_Y,val_Z\n")
                for i, (x, y) in enumerate(zip(xs, ys)):
                    f.write(f"{i},{x:.17g},{y:.17g},{rng.gauss(0, 1):.17g}\n")
            return expected
    raise AssertionError("Could not generate a safely separated correlation case")


def run_and_check_log(binary, csv_path, expected):
    before = os.path.getsize(LOG) if os.path.exists(LOG) else 0
    result = subprocess.run([binary, csv_path], capture_output=True, timeout=15)
    wanted_code = 1 if expected else 0
    assert result.returncode == wanted_code, (
        f"{binary} returned {result.returncode} for a generated case requiring {wanted_code}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(LOG), "Experiment log was not created"
    with open(LOG, "rb") as f:
        f.seek(before)
        appended = f.read().decode("utf-8", errors="replace")
    label = "EVIL" if expected else "CLEAN"
    valid = {f"{csv_path}: {label}", f"{os.path.basename(csv_path)}: {label}"}
    assert any(line.strip() in valid for line in appended.splitlines()), (
        f"Invocation did not append the required filename and label; appended: {appended!r}"
    )


def test_generated_inputs_dynamic_threshold_and_logging():
    """Use unpredictable paths/data and thresholds, checking both submitted and rebuilt code."""
    assert REBUILT is not None
    client = redis_connection()
    rng = random.Random(secrets.randbits(128))
    root = tempfile.mkdtemp(prefix="csv-verifier-")
    cases = []
    try:
        for i in range(8):
            threshold = rng.uniform(0.28, 0.78)
            expected = bool(i % 2)
            name = secrets.token_hex(10) + ".csv"
            path = os.path.join(root, name)
            derived = make_case(path, rng, threshold, expected, negative=bool(i % 3 == 0))
            cases.append((path, threshold, derived))
        rng.shuffle(cases)

        with open(LOG, "w", encoding="utf-8"):
            pass
        for path, threshold, expected in cases:
            client.set("threshold", repr(threshold))
            wait_for_threshold(threshold)
            for binary in (EXE, REBUILT):
                run_and_check_log(binary, path, expected)
    finally:
        client.set("threshold", "0.85")
        wait_for_threshold(0.85)


def test_experiment_log_exists():
    """Retain the original experiment-log existence assertion."""
    assert os.path.isfile(LOG), f"Experiment log not found at {LOG}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
