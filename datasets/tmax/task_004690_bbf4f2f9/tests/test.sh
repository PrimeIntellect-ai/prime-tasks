#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import shlex
import struct
import subprocess
import time
import uuid

import pytest

DRIVER_PATH = "/home/user/wrapper_repo/driver_fixed.py"
ENGINE_PATH = "/app/record_engine"
METRICS_PATH = "/home/user/metrics.log"


@pytest.fixture(scope="session", autouse=True)
def instrument_record_engine():
    token = uuid.uuid4().hex
    real_engine = f"/tmp/record_engine.real.{token}"
    capture_path = f"/tmp/record_engine.input.{token}"
    marker_path = f"/tmp/record_engine.invoked.{token}"

    os.rename(ENGINE_PATH, real_engine)
    wrapper = f'''#!/bin/bash
set -o pipefail
printf 'invoked\\n' > {shlex.quote(marker_path)}
tee {shlex.quote(capture_path)} | {shlex.quote(real_engine)}
'''
    with open(ENGINE_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(ENGINE_PATH, 0o755)

    yield {"capture": capture_path, "marker": marker_path}

    try:
        os.remove(ENGINE_PATH)
    except FileNotFoundError:
        pass
    os.rename(real_engine, ENGINE_PATH)
    for path in (capture_path, marker_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def expected_payload(records):
    chunks = []
    for record in records:
        encoded = record.encode("utf-8")
        chunks.append(struct.pack("i", len(encoded)))
        chunks.append(encoded)
    return b"".join(chunks)


def run_and_verify(data_path, records, probe, timeout=10):
    for path in (METRICS_PATH, probe["capture"], probe["marker"]):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    start_time = time.time()
    res = subprocess.run(
        ["python3", DRIVER_PATH, data_path],
        capture_output=True,
        timeout=timeout,
    )
    actual_time = time.time() - start_time

    assert res.returncode == 0, (
        "Script crashed or failed. stderr: "
        + res.stderr.decode(errors="replace")
    )
    assert os.path.isfile(probe["marker"]), "/app/record_engine was not invoked"
    assert os.path.isfile(probe["capture"]), "No engine input was captured"

    with open(probe["capture"], "rb") as f:
        captured = f.read()
    assert captured == expected_payload(records), (
        "The records sent to /app/record_engine were missing, reordered, or not "
        "serialized as a native integer byte length followed by UTF-8 bytes"
    )

    assert os.path.isfile(METRICS_PATH), f"Missing metrics log at {METRICS_PATH}"
    with open(METRICS_PATH, "r") as f:
        content = f.read().strip()
    try:
        logged_time = float(content)
    except ValueError:
        pytest.fail(
            f"Could not parse logged time from {METRICS_PATH}. Content: {content}"
        )
    assert math.isfinite(logged_time) and logged_time >= 0, (
        "Logged execution time must be a finite, non-negative number"
    )

    return actual_time


def test_driver_fixed_exists():
    assert os.path.isfile(DRIVER_PATH), f"Missing fixed driver script at {DRIVER_PATH}"


def test_execution_time_and_correctness(instrument_record_engine):
    data_path = "/app/eval_data.json"
    with open(data_path, "r") as f:
        records = json.load(f)

    actual_time = run_and_verify(data_path, records, instrument_record_engine)

    threshold = 1.5
    assert actual_time < threshold, (
        f"Execution was too slow. Actual time: {actual_time:.3f}s. "
        f"Threshold is {threshold}s. Did you restore the fast-path flag?"
    )


def test_generated_non_ascii_serialization(instrument_record_engine, tmp_path):
    nonce = secrets.token_hex(20)
    records = [
        f"ASCII-{nonce}",
        f"bullet-•-{nonce}",
        f"accented-café-naïve-{nonce}",
        f"CJK-雪-東京-{nonce}",
        f"emoji-😀-🚀-{nonce}",
        "",
    ]
    data_path = tmp_path / "generated_records.json"
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False)

    run_and_verify(
        str(data_path), records, instrument_record_engine, timeout=3
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
