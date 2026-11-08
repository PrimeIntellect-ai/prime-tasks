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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import subprocess
import time
from decimal import Decimal

import pytest
import requests


def start_server():
    process = subprocess.Popen(
        ["/home/user/serve.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    time.sleep(2)
    return {"process": process, "pgid": process.pid}


def stop_server(server):
    if not server:
        return
    try:
        os.killpg(server["pgid"], signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        server["process"].wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(server["pgid"], signal.SIGKILL)
        except ProcessLookupError:
            pass
        server["process"].wait(timeout=5)
    time.sleep(0.5)


def run_etl():
    result = subprocess.run(["/home/user/etl.sh"], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"etl.sh failed with return code {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def setup_and_run_services():
    etl_script = "/home/user/etl.sh"
    assert os.path.isfile(etl_script), f"Missing ETL script: {etl_script}"
    assert os.access(etl_script, os.X_OK), f"ETL script is not executable: {etl_script}"

    run_etl()

    serve_script = "/home/user/serve.sh"
    assert os.path.isfile(serve_script), f"Missing serve script: {serve_script}"
    assert os.access(serve_script, os.X_OK), f"Serve script is not executable: {serve_script}"

    state = {"server": start_server()}
    yield state
    stop_server(state.get("server"))


def test_final_dataset_exists_and_correct():
    dataset_path = "/home/user/processed/final_dataset.tsv"
    assert os.path.isfile(dataset_path), f"Missing final dataset: {dataset_path}"

    with open(dataset_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines[0] == "event_id\tuser_id\tregion\tmetric_value\tsecure_token", "Incorrect headers in final_dataset.tsv"

    data_rows = lines[1:]
    assert len(data_rows) == 4, f"Expected 4 valid data rows, found {len(data_rows)}"

    expected_rows = {
        "1001\t101\tUS-East\t50.5\tTKN-3F2",
        "1004\t101\tUS-East\t100.0\tTKN-3F5",
        "1005\t102\tEU-West\t25.0\tTKN-3F3",
        "1008\t103\tUS-East\t10.5\tTKN-3E7",
    }

    actual_rows = set(data_rows)
    assert actual_rows == expected_rows, f"Data rows mismatch.\nExpected: {expected_rows}\nActual: {actual_rows}"


def test_etl_runs_log():
    log_path = "/home/user/etl_runs.log"
    assert os.path.isfile(log_path), f"Missing ETL runs log: {log_path}"

    with open(log_path, "r") as f:
        content = f.read()

    assert "Processed 4 valid events" in content, f"Expected 'Processed 4 valid events' in {log_path}, got: {content}"


def test_serve_us_east_valid():
    url = "http://127.0.0.1:8080/query?region=US-East"
    headers = {"Authorization": "Bearer etl_secret_2024"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Request to {url} failed: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert data.get("region") == "US-East", f"Expected region US-East, got {data.get('region')}"
    assert float(data.get("total_metric", 0)) == 161.0, f"Expected total_metric 161.0, got {data.get('total_metric')}"


def test_serve_eu_west_valid():
    url = "http://127.0.0.1:8080/query?region=EU-West"
    headers = {"Authorization": "Bearer etl_secret_2024"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Request to {url} failed: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert data.get("region") == "EU-West", f"Expected region EU-West, got {data.get('region')}"
    assert float(data.get("total_metric", 0)) == 25.0, f"Expected total_metric 25.0, got {data.get('total_metric')}"


def test_serve_invalid_auth():
    url = "http://127.0.0.1:8080/query?region=US-East"

    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Request to {url} failed: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"


def test_serve_missing_params():
    url = "http://127.0.0.1:8080/query"
    headers = {"Authorization": "Bearer etl_secret_2024"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Request to {url} failed: {e}")

    assert response.status_code >= 400, f"Expected a 400+ error status code for missing params, got {response.status_code}. Response: {response.text}"


def anonymize(user_id, event_id):
    result = subprocess.run(
        ["/app/anonymizer"],
        input=f"{user_id} {event_id}\n",
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def test_dynamic_partitions_join_filter_transform_and_service(setup_and_run_services):
    state = setup_and_run_services
    stop_server(state["server"])
    state["server"] = None

    nonce = random.SystemRandom().randrange(10000, 90000)
    uid1, uid2, uid3 = 800000 + nonce * 3, 800001 + nonce * 3, 800002 + nonce * 3
    eid1, eid2, eid3 = 900000 + nonce * 10, 900001 + nonce * 10, 900002 + nonce * 10
    region1 = f"AP-North-{nonce}"
    region2 = f"SA-South-{nonce}"
    metric1 = f"{nonce % 71 + 11}.25"
    metric2 = f"{nonce % 43 + 7}.75"
    metric3 = f"{nonce % 29 + 3}.125"

    with open("/home/user/data/users.csv", "a") as f:
        f.write(f"{uid1},{region1},premium\n")
        f.write(f"{uid2},{region1},basic\n")
        f.write(f"{uid3},{region2},premium\n")

    partition1 = f"/home/user/data/logs/2099-01-{nonce % 9 + 10:02d}"
    partition2 = f"/home/user/data/logs/2099-02-{nonce % 9 + 10:02d}"
    os.makedirs(partition1, exist_ok=True)
    os.makedirs(partition2, exist_ok=True)

    with open(os.path.join(partition1, "events.tsv"), "w") as f:
        f.write("event_id\tuser_id\ttimestamp\tmetric_value\n")
        f.write(f"{eid1}\t{uid1}\t2099-01-01T00:00:00Z\t{metric1}\n")
        f.write(f"{eid1 + 3}\t{uid1}\t2099-01-01T00:01:00Z\t-3.5\n")
        f.write(f"{eid1 + 4}\t{uid2}\t2099-01-01T00:02:00Z\tnot-a-number\n")
        f.write(f"{eid1 + 5}\t\t2099-01-01T00:03:00Z\t18.0\n")
        f.write(f"{eid1 + 6}\t{uid3 + 100}\t2099-01-01T00:04:00Z\t19.0\n")

    with open(os.path.join(partition2, "events.tsv"), "w") as f:
        f.write("event_id\tuser_id\ttimestamp\tmetric_value\n")
        f.write(f"{eid2}\t{uid2}\t2099-02-01T00:00:00Z\t{metric2}\n")
        f.write(f"{eid3}\t{uid3}\t2099-02-01T00:01:00Z\t{metric3}\n")
        f.write(f"{eid3 + 1}\t{uid3}\t2099-02-01T00:02:00Z\t\n")

    expected = {
        "1001": ("101", "US-East", Decimal("50.5"), "TKN-3F2"),
        "1004": ("101", "US-East", Decimal("100.0"), "TKN-3F5"),
        "1005": ("102", "EU-West", Decimal("25.0"), "TKN-3F3"),
        "1008": ("103", "US-East", Decimal("10.5"), "TKN-3E7"),
        str(eid1): (str(uid1), region1, Decimal(metric1), anonymize(uid1, eid1)),
        str(eid2): (str(uid2), region1, Decimal(metric2), anonymize(uid2, eid2)),
        str(eid3): (str(uid3), region2, Decimal(metric3), anonymize(uid3, eid3)),
    }

    log_path = "/home/user/etl_runs.log"
    with open(log_path, "r") as f:
        old_log = f.read()

    run_etl()

    with open("/home/user/processed/final_dataset.tsv", "r") as f:
        rows = [line.rstrip("\n") for line in f if line.strip()]

    assert rows[0] == "event_id\tuser_id\tregion\tmetric_value\tsecure_token"
    assert len(rows[1:]) == len(expected), f"Expected {len(expected)} valid rows, got {len(rows[1:])}"

    actual = {}
    for row in rows[1:]:
        fields = row.split("\t")
        assert len(fields) == 5, f"Malformed output row: {row!r}"
        event_id, user_id, region, metric, token = fields
        assert event_id not in actual, f"Duplicate event row: {event_id}"
        try:
            parsed_metric = Decimal(metric)
        except Exception:
            pytest.fail(f"Non-numeric output metric in row: {row!r}")
        actual[event_id] = (user_id, region, parsed_metric, token)

    assert actual == expected, f"Dynamic ETL output mismatch.\nExpected: {expected}\nActual: {actual}"

    with open(log_path, "r") as f:
        new_log = f.read()
    assert new_log.startswith(old_log), "etl_runs.log was overwritten instead of appended"
    appended = new_log[len(old_log):]
    assert re.search(r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Processed 7 valid events\s*$", appended), appended

    state["server"] = start_server()
    auth = {"Authorization": "Bearer etl_secret_2024"}

    for region, total in (
        (region1, Decimal(metric1) + Decimal(metric2)),
        (region2, Decimal(metric3)),
    ):
        response = requests.get(
            "http://127.0.0.1:8080/query",
            params={"region": region},
            headers=auth,
            timeout=5,
        )
        assert response.status_code == 200, response.text
        payload = response.json()
        assert payload.get("region") == region
        assert Decimal(str(payload.get("total_metric"))) == total

    bad_auth = requests.get(
        "http://127.0.0.1:8080/query",
        params={"region": region1},
        headers={"Authorization": "Bearer etl_secret_2024_extra"},
        timeout=5,
    )
    assert bad_auth.status_code == 401, f"Non-exact authorization was accepted: {bad_auth.status_code} {bad_auth.text}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
