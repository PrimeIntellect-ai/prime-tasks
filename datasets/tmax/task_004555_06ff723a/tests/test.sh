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
import csv
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import uuid

import requests

CSV_PATH = "/home/user/processed_graph.csv"
MANIFEST_PATH = "/home/user/manifests.jsonl"
SERVER_PATH = "/app/backup-lineage-server/server.py"
BASE_URL = "http://127.0.0.1:9090/lineage/"


def read_manifest():
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def expected_lineage(backup_id, parent_by_id):
    result = []
    seen = set()
    parent = parent_by_id[backup_id]
    while parent is not None and parent != "":
        assert parent not in seen, "Manifest contains a dependency cycle"
        seen.add(parent)
        result.append(parent)
        parent = parent_by_id.get(parent)
    return result


def test_csv_exists_and_format():
    assert os.path.isfile(CSV_PATH), f"Processed CSV file {CSV_PATH} does not exist. Did you create it?"

    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, f"CSV file {CSV_PATH} is empty."

        expected_header = ["backup_id", "parent_backup_id", "size_bytes", "status"]
        assert header == expected_header, f"Incorrect CSV header. Expected {expected_header}, got {header}"

        rows = list(reader)
        assert len(rows) == 5, f"Expected 5 data rows in CSV, found {len(rows)}."

        # Preserve the original mapping checks.
        assert rows[0] == ["bck_001", "", "1024", "SUCCESS"], f"Incorrect first row mapping: {rows[0]}"
        assert rows[1] == ["bck_002", "bck_001", "2048", "SUCCESS"], f"Incorrect second row mapping: {rows[1]}"

        manifests = read_manifest()
        expected_rows = [
            [
                str(doc["_id"]),
                "" if doc["metadata"]["parent"] is None else str(doc["metadata"]["parent"]),
                str(doc["metadata"]["size"]),
                str(doc["state"]),
            ]
            for doc in manifests
        ]
        assert rows == expected_rows, f"CSV rows do not exactly match the manifest mapping. Expected {expected_rows}, got {rows}"


def test_server_endpoints():
    try:
        requests.get(BASE_URL + "bck_001", timeout=3)
    except requests.exceptions.RequestException as e:
        assert False, f"Server is not reachable on 127.0.0.1:9090. Exception: {e}"

    # Preserve the original endpoint assertions.
    original_cases = {
        "bck_001": [],
        "bck_002": ["bck_001"],
        "bck_004": ["bck_003", "bck_002", "bck_001"],
    }
    for backup_id, expected in original_cases.items():
        response = requests.get(BASE_URL + backup_id, timeout=3)
        assert response.status_code == 200, f"Expected HTTP 200 for {backup_id}, got {response.status_code}. Response body: {response.text}"
        try:
            data = response.json()
        except ValueError:
            assert False, f"Response for {backup_id} is not valid JSON. Response body: {response.text}"
        assert isinstance(data, list), f"Expected a JSON array response for {backup_id}, got {type(data).__name__}"
        assert set(data) == set(expected), f"Expected lineage ancestors {expected} for {backup_id}, got {data}"
        assert data == expected, f"Lineage for {backup_id} is not in chronological parent-to-root order: expected {expected}, got {data}"

    manifests = read_manifest()
    parent_by_id = {str(doc["_id"]): doc["metadata"]["parent"] for doc in manifests}
    for backup_id in parent_by_id:
        expected = expected_lineage(backup_id, parent_by_id)
        response = requests.get(BASE_URL + backup_id, timeout=3)
        assert response.status_code == 200, f"Expected HTTP 200 for {backup_id}, got {response.status_code}. Response body: {response.text}"
        try:
            data = response.json()
        except ValueError:
            assert False, f"Response for {backup_id} is not valid JSON. Response body: {response.text}"
        assert isinstance(data, list), f"Expected a JSON array response for {backup_id}, got {type(data).__name__}"
        assert data == expected, f"Expected chronological lineage {expected} for {backup_id}, got {data}"

    missing_id = "missing_" + uuid.uuid4().hex
    response = requests.get(BASE_URL + missing_id, timeout=3)
    assert response.status_code == 404, f"Expected HTTP 404 for unknown backup {missing_id}, got {response.status_code}"


def test_patched_server_uses_data_path_and_builds_dynamic_graph():
    assert os.path.isfile(SERVER_PATH), f"Vendored server file {SERVER_PATH} is missing"

    ids = ["dynamic_" + uuid.uuid4().hex for _ in range(5)]
    dynamic_rows = [
        [ids[0], "", "11", "SUCCESS"],
        [ids[1], ids[0], "22", "SUCCESS"],
        [ids[2], ids[1], "33", "SUCCESS"],
        [ids[3], ids[2], "44", "FAILED"],
        [ids[4], "", "55", "SUCCESS"],
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        dynamic_csv = os.path.join(tmpdir, "dynamic_graph.csv")
        with open(dynamic_csv, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["backup_id", "parent_backup_id", "size_bytes", "status"])
            writer.writerows(dynamic_rows)

        helper = os.path.join(tmpdir, "exercise_server.py")
        with open(helper, "w", encoding="utf-8") as f:
            f.write(textwrap.dedent("""
                import importlib.util
                import json
                import os
                import sys

                server_path = sys.argv[1]
                ids = json.loads(sys.argv[2])
                spec = importlib.util.spec_from_file_location("submitted_backup_lineage_server", server_path)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)

                assert hasattr(module, "load_graph"), "server.py does not define load_graph()"
                assert hasattr(module, "app"), "server.py does not expose its Flask app"
                if hasattr(module, "G") and hasattr(module.G, "clear"):
                    module.G.clear()
                module.load_graph()

                client = module.app.test_client()
                expected = {
                    ids[0]: [],
                    ids[1]: [ids[0]],
                    ids[2]: [ids[1], ids[0]],
                    ids[3]: [ids[2], ids[1], ids[0]],
                    ids[4]: [],
                }
                for backup_id, lineage in expected.items():
                    response = client.get("/lineage/" + backup_id)
                    assert response.status_code == 200, (backup_id, response.status_code, response.get_data(as_text=True))
                    data = response.get_json()
                    assert isinstance(data, list), (backup_id, data)
                    assert data == lineage, (backup_id, lineage, data)

                response = client.get("/lineage/unknown_dynamic_id")
                assert response.status_code == 404, response.status_code
            """))

        env = os.environ.copy()
        env["DATA_PATH"] = dynamic_csv
        result = subprocess.run(
            [sys.executable, helper, SERVER_PATH, json.dumps(ids)],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            "Patched server.py failed when exercised with a verifier-generated DATA_PATH and graph. "
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
