#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import urllib.request
import urllib.parse
from urllib.error import URLError


def get_raw_data_stats():
    raw_path = "/home/user/raw_data.csv"
    assert os.path.exists(raw_path), f"Original raw data {raw_path} is missing."

    with open(raw_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    temps = []
    missing_count = 0
    outlier_count = 0

    for row in rows:
        t = row['temperature']
        if t.strip() == '':
            missing_count += 1
        else:
            temps.append(float(t))

        h = float(row['humidity'])
        if h < 0 or h > 100:
            outlier_count += 1

    temps.sort()
    n = len(temps)
    if n % 2 == 1:
        median_temp = temps[n // 2]
    else:
        median_temp = (temps[n // 2 - 1] + temps[n // 2]) / 2.0

    return {
        "missing_count": missing_count,
        "outlier_count": outlier_count,
        "median_temp": median_temp,
        "total_rows": len(rows),
        "rows": rows,
    }


def expected_clean_rows(stats):
    expected = []
    for row in stats["rows"]:
        humidity = float(row["humidity"])
        if humidity < 0 or humidity > 100:
            continue
        temperature = (stats["median_temp"] if row["temperature"].strip() == ''
                       else float(row["temperature"]))
        expected.append((row["timestamp"], temperature, humidity))
    return expected


def test_cleaned_data_exists_and_content():
    stats = get_raw_data_stats()
    clean_path = "/home/user/cleaned_data.csv"
    assert os.path.exists(clean_path), f"Cleaned data file {clean_path} does not exist."

    with open(clean_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['timestamp', 'temperature', 'humidity'], f"Header is incorrect: {header}"
        rows = list(reader)

    expected_rows = stats["total_rows"] - stats["outlier_count"]
    assert len(rows) == expected_rows, f"Expected {expected_rows} rows in cleaned data, got {len(rows)}."

    imputed_count = 0
    for row in rows:
        assert len(row) == 3, f"Cleaned row has the wrong number of columns: {row}"
        temp = float(row[1])
        humidity = float(row[2])
        assert math.isfinite(temp), f"Found non-finite temperature value {row[1]}."
        assert math.isfinite(humidity), f"Found non-finite humidity value {row[2]}."
        assert 0 <= humidity <= 100, f"Found outlier humidity value {humidity} in cleaned data."
        if abs(temp - stats["median_temp"]) < 1e-5:
            imputed_count += 1

    # Preserve the original assertion about the number of median-valued rows.
    assert imputed_count >= stats["missing_count"], f"Expected at least {stats['missing_count']} median values in cleaned data, found {imputed_count}."

    # Every retained row must be the corresponding original row, in original order,
    # with only a missing temperature replaced by the computed median.
    expected = expected_clean_rows(stats)
    assert len(rows) == len(expected)
    for index, (actual, wanted) in enumerate(zip(rows, expected), start=2):
        wanted_timestamp, wanted_temperature, wanted_humidity = wanted
        assert actual[0] == wanted_timestamp, (
            f"Timestamp/order mismatch on CSV line {index}: expected {wanted_timestamp!r}, got {actual[0]!r}."
        )
        actual_temperature = float(actual[1])
        actual_humidity = float(actual[2])
        assert math.isclose(actual_temperature, wanted_temperature, rel_tol=0.0, abs_tol=1e-9), (
            f"Temperature mismatch on CSV line {index}: expected {wanted_temperature}, got {actual_temperature}."
        )
        assert math.isclose(actual_humidity, wanted_humidity, rel_tol=0.0, abs_tol=1e-9), (
            f"Humidity mismatch on CSV line {index}: expected {wanted_humidity}, got {actual_humidity}."
        )


def mlflow_get(path, params):
    query = urllib.parse.urlencode(params)
    url = f"http://127.0.0.1:5000{path}?{query}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"MLflow returned HTTP {response.status} for {path}."
            return json.loads(response.read().decode('utf-8'))
    except (URLError, TimeoutError, json.JSONDecodeError) as e:
        assert False, f"Failed to connect to MLflow server or retrieve data: {e}"


def mlflow_owns_port_5000():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    local = fields[1]
                    address, port = local.rsplit(":", 1)
                    if port.upper() != "1388":
                        continue
                    if table.endswith("tcp") and address.upper() != "0100007F":
                        continue
                    socket_inodes.add(fields[9])
        except OSError:
            pass

    for proc_name in os.listdir("/proc"):
        if not proc_name.isdigit():
            continue
        proc_dir = os.path.join("/proc", proc_name)
        try:
            owns_socket = False
            for fd in os.listdir(os.path.join(proc_dir, "fd")):
                target = os.readlink(os.path.join(proc_dir, "fd", fd))
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    owns_socket = True
                    break
            if not owns_socket:
                continue
            evidence = b""
            with open(os.path.join(proc_dir, "cmdline"), "rb") as f:
                evidence += f.read()
            try:
                with open(os.path.join(proc_dir, "maps"), "rb") as f:
                    evidence += f.read()
            except OSError:
                pass
            if b"mlflow" in evidence.lower():
                return True
        except (OSError, PermissionError):
            continue
    return False


def test_mlflow_tracking():
    stats = get_raw_data_stats()
    run_id_path = "/home/user/run_id.txt"
    assert os.path.exists(run_id_path), f"Run ID file {run_id_path} does not exist."

    with open(run_id_path, 'r') as f:
        run_id = f.read().strip()

    assert run_id, "Run ID file is empty."
    assert mlflow_owns_port_5000(), "Port 5000 is not owned by a running MLflow server process."

    data = mlflow_get("/api/2.0/mlflow/runs/get", {"run_id": run_id})
    assert 'run' in data and 'data' in data['run'] and 'metrics' in data['run']['data'], "Invalid MLflow API response structure."
    assert 'info' in data['run'], "MLflow run response is missing run information."

    info = data['run']['info']
    returned_run_id = info.get('run_id', info.get('run_uuid'))
    assert returned_run_id == run_id, f"MLflow returned run {returned_run_id!r}, not {run_id!r}."
    experiment_id = info.get('experiment_id')
    assert experiment_id is not None, "MLflow run is missing its experiment ID."

    experiment_data = mlflow_get(
        "/api/2.0/mlflow/experiments/get", {"experiment_id": experiment_id}
    )
    assert 'experiment' in experiment_data, "Invalid MLflow experiment API response structure."
    assert experiment_data['experiment'].get('name') == 'climate_cleaning', (
        f"Expected experiment name 'climate_cleaning', got {experiment_data['experiment'].get('name')!r}."
    )

    metrics = data['run']['data']['metrics']
    metric_dict = {m['key']: m['value'] for m in metrics}

    assert 'missing_imputed' in metric_dict, "Metric 'missing_imputed' was not logged."
    assert metric_dict['missing_imputed'] == stats["missing_count"], f"Expected 'missing_imputed' to be {stats['missing_count']}, got {metric_dict['missing_imputed']}."

    assert 'rows_removed' in metric_dict, "Metric 'rows_removed' was not logged."
    assert metric_dict['rows_removed'] == stats["outlier_count"], f"Expected 'rows_removed' to be {stats['outlier_count']}, got {metric_dict['rows_removed']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
