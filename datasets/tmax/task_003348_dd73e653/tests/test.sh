#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import datetime
import json
import os
import re
import secrets
import shlex
import stat
import subprocess
import time
import uuid

import pytest
import requests

PIPELINE = "/home/user/pipeline.sh"
SCORE_CALC = "/app/score_calc"
RUN_ID = uuid.uuid4().hex
REAL_PIPELINE = f"/home/user/.pipeline.verifier.{RUN_ID}"
REAL_SCORE = f"/app/.score_calc.verifier.{RUN_ID}"
PIPE_CALLS = f"/tmp/pipeline_calls.{RUN_ID}"
SCORE_CALLS = f"/tmp/score_calls.{RUN_ID}"
PIPE_TOKEN = secrets.token_hex(16)


def get_expected_results(batch_name):
    # Compute expected results dynamically based on the CSV files
    csv_path = f"/home/user/data/{batch_name}.csv"
    if not os.path.exists(csv_path):
        return None

    scores = []
    anomalies = 0
    with open(csv_path, 'r') as f:
        lines = f.read().strip().split('\n')
        if len(lines) > 1:
            for line in lines[1:]:
                parts = line.split(',')
                if len(parts) == 4:
                    v1, v2, v3 = float(parts[1]), float(parts[2]), float(parts[3])
                    score = (0.5 * v1) + (1.2 * v2) + (0.8 * v3)
                    scores.append(score)
                    if score > 5.0:
                        anomalies += 1

    if not scores:
        return {"batch": batch_name, "average_score": 0.0, "anomalies": 0}

    avg_score = sum(scores) / len(scores)
    return {"batch": batch_name, "average_score": round(avg_score, 2), "anomalies": anomalies}


def request_batch(batch_name):
    try:
        return requests.get(
            "http://127.0.0.1:8080/process",
            params={"batch": batch_name},
            timeout=8,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")


@pytest.fixture(scope="session", autouse=True)
def instrument_required_artifacts():
    assert os.path.isfile(PIPELINE), f"{PIPELINE} does not exist or is not a regular file"
    mode = os.stat(PIPELINE).st_mode
    assert mode & stat.S_IXUSR, f"{PIPELINE} is not executable"
    with open(PIPELINE, "rb") as f:
        first_line = f.readline(256).decode("utf-8", "replace").strip()
    assert re.match(r"^#!\s*(/bin/bash|/usr/bin/bash|/usr/bin/env\s+(?:-S\s+)?bash)(?:\s|$)", first_line), \
        f"{PIPELINE} must have a Bash shebang"
    syntax = subprocess.run(["/bin/bash", "-n", PIPELINE], capture_output=True, text=True)
    assert syntax.returncode == 0, f"{PIPELINE} is not valid Bash: {syntax.stderr}"
    assert os.path.isfile(SCORE_CALC) and os.access(SCORE_CALC, os.X_OK), \
        f"{SCORE_CALC} is missing or not executable"

    open(PIPE_CALLS, "w").close()
    open(SCORE_CALLS, "w").close()
    os.chmod(PIPE_CALLS, 0o666)
    os.chmod(SCORE_CALLS, 0o666)

    pipeline_moved = False
    score_moved = False
    try:
        os.rename(PIPELINE, REAL_PIPELINE)
        pipeline_moved = True
        os.rename(SCORE_CALC, REAL_SCORE)
        score_moved = True

        pipeline_wrapper = f'''#!/bin/bash
printf '%s\\n' "$*" >> {shlex.quote(PIPE_CALLS)}
export VERIFIER_PIPELINE_TOKEN={shlex.quote(PIPE_TOKEN)}
exec {shlex.quote(REAL_PIPELINE)} "$@"
'''
        score_wrapper = f'''#!/bin/bash
printf '%s\\t%s\\t%s\\t%s\\n' "${{VERIFIER_PIPELINE_TOKEN:-}}" "$1" "$2" "$3" >> {shlex.quote(SCORE_CALLS)}
exec {shlex.quote(REAL_SCORE)} "$@"
'''
        with open(PIPELINE, "w") as f:
            f.write(pipeline_wrapper)
        with open(SCORE_CALC, "w") as f:
            f.write(score_wrapper)
        os.chmod(PIPELINE, 0o755)
        os.chmod(SCORE_CALC, 0o755)

        yield
    finally:
        try:
            if pipeline_moved:
                if os.path.lexists(PIPELINE):
                    os.unlink(PIPELINE)
                os.rename(REAL_PIPELINE, PIPELINE)
        finally:
            if score_moved:
                if os.path.lexists(SCORE_CALC):
                    os.unlink(SCORE_CALC)
                os.rename(REAL_SCORE, SCORE_CALC)
        for path in (PIPE_CALLS, SCORE_CALLS):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_api_test_batch():
    expected = get_expected_results("test_batch")
    assert expected is not None, "test_batch.csv is missing"

    response = request_batch("test_batch")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "batch" in data, "Missing 'batch' in JSON response"
    assert "average_score" in data, "Missing 'average_score' in JSON response"
    assert "anomalies" in data, "Missing 'anomalies' in JSON response"

    assert data["batch"] == expected["batch"], f"Expected batch {expected['batch']}, got {data['batch']}"
    assert abs(data["average_score"] - expected["average_score"]) < 1e-2, f"Expected average_score {expected['average_score']}, got {data['average_score']}"
    assert data["anomalies"] == expected["anomalies"], f"Expected anomalies {expected['anomalies']}, got {data['anomalies']}"


def test_api_batch1():
    expected = get_expected_results("batch1")
    assert expected is not None, "batch1.csv is missing"

    response = request_batch("batch1")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert data["batch"] == expected["batch"], f"Expected batch {expected['batch']}, got {data['batch']}"
    assert abs(data["average_score"] - expected["average_score"]) < 1e-2, f"Expected average_score {expected['average_score']}, got {data['average_score']}"
    assert data["anomalies"] == expected["anomalies"], f"Expected anomalies {expected['anomalies']}, got {data['anomalies']}"


def test_unseen_batch_executes_pipeline_and_oracle():
    batch_name = "verify_" + secrets.token_hex(8)
    csv_path = f"/home/user/data/{batch_name}.csv"
    row_count = 5 + secrets.randbelow(4)
    rows = []
    for i in range(row_count):
        vals = tuple(f"{(secrets.randbelow(989) + 11) / 100:.2f}" for _ in range(3))
        rows.append((str(7000 + i),) + vals)

    with open(csv_path, "w") as f:
        f.write("id,v1,v2,v3\n")
        for row in rows:
            f.write(",".join(row) + "\n")
    os.chmod(csv_path, 0o644)

    scores = []
    for _, v1, v2, v3 in rows:
        result = subprocess.run([REAL_SCORE, v1, v2, v3], check=True, capture_output=True, text=True)
        scores.append(float(result.stdout.strip()))
    expected_avg = round(sum(scores) / len(scores), 2)
    expected_anomalies = sum(score > 5.0 for score in scores)

    with open(PIPE_CALLS) as f:
        pipeline_before = len(f.readlines())
    with open(SCORE_CALLS) as f:
        score_before = len(f.readlines())
    log_path = "/home/user/tracking.log"
    log_offset = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    started = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=2)

    try:
        response = request_batch(batch_name)
        finished = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=2)
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")

        assert data.get("batch") == batch_name
        assert isinstance(data.get("average_score"), (int, float))
        assert abs(data["average_score"] - expected_avg) < 1e-2, \
            f"Expected average_score {expected_avg}, got {data['average_score']}"
        assert data.get("anomalies") == expected_anomalies

        with open(PIPE_CALLS) as f:
            new_pipeline_calls = [line.strip() for line in f.readlines()[pipeline_before:]]
        assert any(line.split() == [batch_name] for line in new_pipeline_calls), \
            "The API did not invoke /home/user/pipeline.sh with the unseen batch"

        with open(SCORE_CALLS) as f:
            new_score_calls = [line.rstrip("\n").split("\t") for line in f.readlines()[score_before:]]
        inherited_calls = [parts for parts in new_score_calls if len(parts) == 4 and parts[0] == PIPE_TOKEN]
        assert len(inherited_calls) == row_count, \
            "The pipeline did not invoke /app/score_calc exactly once for every CSV row"
        actual_values = collections.Counter(tuple(float(x) for x in parts[1:]) for parts in inherited_calls)
        expected_values = collections.Counter(tuple(float(x) for x in row[1:]) for row in rows)
        assert actual_values == expected_values, \
            "The pipeline did not pass each unseen row's v1, v2, and v3 values to /app/score_calc"

        assert os.path.exists(log_path), "tracking.log was not created"
        with open(log_path, "r") as f:
            f.seek(log_offset)
            new_log = f.read()
        pattern = re.compile(
            rf"^\[(\d{{4}}-\d{{2}}-\d{{2}}T\d{{2}}:\d{{2}}:\d{{2}}Z)\] "
            rf"BATCH={re.escape(batch_name)} AVG=([0-9.]+) ANOMALIES=(\d+)$"
        )
        matches = [pattern.match(line) for line in new_log.splitlines()]
        matches = [match for match in matches if match]
        assert matches, "The unseen API request did not append the required tracking line"
        match = matches[-1]
        timestamp = datetime.datetime.strptime(match.group(1), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
        assert started <= timestamp <= finished, "Tracking timestamp is not current UTC time"
        assert abs(float(match.group(2)) - expected_avg) < 0.1
        assert int(match.group(3)) == expected_anomalies
    finally:
        try:
            os.unlink(csv_path)
        except FileNotFoundError:
            pass


def test_tracking_log():
    log_path = "/home/user/tracking.log"
    assert os.path.exists(log_path), f"Tracking log {log_path} does not exist"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content, "Tracking log is empty"
    lines = content.split('\n')

    # Format: [<timestamp>] BATCH=<batch_name> AVG=<average_score> ANOMALIES=<count>
    pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\] BATCH=(\w+) AVG=([0-9.]+) ANOMALIES=(\d+)$")

    found_test_batch = False
    found_batch1 = False

    for line in lines:
        match = pattern.match(line)
        assert match, f"Log line does not match expected format: {line}"

        batch = match.group(1)
        avg = float(match.group(2))
        anom = int(match.group(3))

        expected = get_expected_results(batch)
        if expected:
            assert abs(avg - expected["average_score"]) < 0.1, f"Log average score {avg} does not match expected {expected['average_score']} for batch {batch}"
            assert anom == expected["anomalies"], f"Log anomalies {anom} does not match expected {expected['anomalies']} for batch {batch}"

            if batch == "test_batch":
                found_test_batch = True
            elif batch == "batch1":
                found_batch1 = True

    assert found_test_batch, "test_batch was not found in tracking.log"
    assert found_batch1, "batch1 was not found in tracking.log"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
