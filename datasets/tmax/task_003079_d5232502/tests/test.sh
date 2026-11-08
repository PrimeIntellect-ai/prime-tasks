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
echo "0" > /logs/verifier/reward.txt

BACKUP_DIR=$(mktemp -d)
cp /home/user/datasets/documents.jsonl "$BACKUP_DIR/documents.jsonl"
cp /home/user/datasets/metadata.csv "$BACKUP_DIR/metadata.csv"
restore_datasets() {
    cp "$BACKUP_DIR/documents.jsonl" /home/user/datasets/documents.jsonl
    cp "$BACKUP_DIR/metadata.csv" /home/user/datasets/metadata.csv
    rm -rf "$BACKUP_DIR"
}
trap restore_datasets EXIT

export VERIFY_TOKEN="verify_$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
python3 - <<'PY'
import csv
import json
import os

token = os.environ["VERIFY_TOKEN"]
documents = [
    {"doc_id": token + "_old", "title": "Old " + token, "content": "verification"},
    {"doc_id": token + "_new", "title": "New " + token, "content": "verification"},
    {"doc_id": token + "_mid", "title": "Mid " + token, "content": "verification"},
    {"doc_id": token + "_decoy", "title": "Decoy " + token, "content": "verification"},
    {"doc_id": token + "_no_metadata", "title": "No metadata " + token, "content": "verification"},
]
with open("/home/user/datasets/documents.jsonl", "a", encoding="utf-8") as f:
    for document in documents:
        f.write(json.dumps(document) + "\n")

with open("/home/user/datasets/metadata.csv", "a", encoding="utf-8", newline="") as f:
    writer = csv.writer(f)
    writer.writerow([token + "_old", token, "1700000001"])
    writer.writerow([token + "_new", token, "1900000003"])
    writer.writerow([token + "_mid", token, "1800000002"])
    writer.writerow([token + "_decoy", token + "_other", "1999999999"])
    writer.writerow([token + "_missing_document", token, "2000000000"])
PY

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import time
import uuid

import pytest
import requests

BASE_URL = "http://localhost:8080/dataset"
FIELDS = ("doc_id", "title", "author", "timestamp_published")


def wait_for_server(url, timeout=10):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.RequestException:
            time.sleep(0.25)
    return False


def expected_records(author, limit):
    documents = {}
    with open("/home/user/datasets/documents.jsonl", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                document = json.loads(line)
                documents[str(document["doc_id"])] = document

    joined = []
    with open("/home/user/datasets/metadata.csv", encoding="utf-8", newline="") as f:
        for metadata in csv.DictReader(f):
            if metadata["author"] != author:
                continue
            document = documents.get(str(metadata["doc_id"]))
            if document is None:
                continue
            joined.append({
                "doc_id": str(document["doc_id"]),
                "title": str(document["title"]),
                "author": str(metadata["author"]),
                "timestamp_published": str(metadata["timestamp_published"]),
            })

    joined.sort(key=lambda row: int(row["timestamp_published"]), reverse=True)
    return joined[:limit]


def request_dataset(author, limit):
    response = requests.get(BASE_URL, params={"author": author, "limit": limit}, timeout=5)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("application/json"), \
        f"Expected application/json Content-Type, got {response.headers.get('Content-Type')!r}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert isinstance(data, list), "Expected response to be a JSON array."
    return data


def project_records(data):
    projected = []
    for record in data:
        assert isinstance(record, dict), "Each result must be a JSON object."
        for field in FIELDS:
            assert field in record, f"Missing {field!r} in response"
        projected.append({field: str(record[field]) for field in FIELDS})
    return projected


def assert_query(author, limit):
    data = request_dataset(author, limit)
    assert len(data) <= limit, f"Expected at most {limit} results, got {len(data)}"
    assert project_records(data) == expected_records(author, limit)
    return data


def test_handler_script_exists():
    assert os.path.isfile("/home/user/handler.sh"), "Handler script /home/user/handler.sh is missing."
    result = subprocess.run(["bash", "-n", "/home/user/handler.sh"], capture_output=True, text=True)
    assert result.returncode == 0, f"Handler is not valid Bash: {result.stderr}"


def test_server_running_and_responds():
    url = "http://localhost:8080/dataset?author=Ada&limit=1"
    server_up = wait_for_server(url, timeout=5)
    assert server_up, "Server is not running or not reachable on port 8080."


def test_api_response_ada_limit_1():
    data = request_dataset("Ada", 1)
    assert len(data) == 1, f"Expected exactly 1 result due to limit=1, got {len(data)}"

    record = data[0]
    assert "doc_id" in record, "Missing 'doc_id' in response"
    assert "title" in record, "Missing 'title' in response"
    assert "author" in record, "Missing 'author' in response"
    assert "timestamp_published" in record, "Missing 'timestamp_published' in response"
    assert record["author"] == "Ada", f"Expected author 'Ada', got {record['author']}"
    assert project_records(data) == expected_records("Ada", 1)


def test_api_response_sorting_and_limit():
    data = request_dataset("Ada", 2)
    assert len(data) <= 2, f"Expected at most 2 results due to limit=2, got {len(data)}"
    if len(data) == 2:
        ts1 = int(data[0].get("timestamp_published", 0))
        ts2 = int(data[1].get("timestamp_published", 0))
        assert ts1 >= ts2, "Results are not sorted by timestamp_published in descending order."
    assert project_records(data) == expected_records("Ada", 2)


def test_dynamic_join_filter_sort_and_pagination():
    author = os.environ["VERIFY_TOKEN"]
    assert len(expected_records(author, 10)) == 3
    assert_query(author, 1)
    assert_query(author, 2)
    assert_query(author, 10)
    assert_query(author + "_other", 10)


def test_other_existing_author_and_empty_result():
    assert_query("John Doe", 5)
    assert_query("author_which_does_not_exist_" + uuid.uuid4().hex, 5)


def test_perturbation_fixed():
    request_parser_path = "/app/bashttpd-1.0/lib/request_parser.sh"
    assert os.path.isfile(request_parser_path), f"Missing {request_parser_path}"
    with open(request_parser_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert content, "Request parser is empty"

    raw_query = "author=" + uuid.uuid4().hex + "&limit=7&extra=a%20b"
    request_uri = "/dataset?" + raw_query
    command = 'source /app/bashttpd-1.0/lib/request_parser.sh; printf "%s" "$QUERY_STRING"'
    result = subprocess.run(
        ["bash", "-c", command],
        env={**os.environ, "REQUEST_URI": request_uri},
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Request parser failed: {result.stderr}"
    assert result.stdout == raw_query, \
        f"QUERY_STRING should contain the raw query {raw_query!r}, got {result.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
