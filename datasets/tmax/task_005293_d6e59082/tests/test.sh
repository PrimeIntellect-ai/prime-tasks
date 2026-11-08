#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

# Add unpredictable catalog entries so fixed responses cannot pass. The submitted
# service is then restarted from /home/user/api.py so it must load the live data.
python3 - <<'PY' || status=1
import csv
import json
import os
import random
import string

import psycopg2

api_path = "/home/user/api.py"
if not os.path.isfile(api_path) or os.path.islink(api_path) or os.path.getsize(api_path) == 0:
    raise RuntimeError("/home/user/api.py must be a non-empty regular file")

def word(n=18):
    return "v" + "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(n))

common = word()
base_id = random.SystemRandom().randint(1000000, 1900000000)
downloads = [9, 999, 99999, 99999999]
rows = []
for i in range(4):
    rows.append({
        "id": base_id + i,
        "name": "Verifier-" + word(10),
        "description": f"{common} {word()} {word()}",
        "downloads": downloads[i],
    })

conn = psycopg2.connect(dbname="catalog", user="postgres", password="postgres", host="127.0.0.1", port=5432)
try:
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                "INSERT INTO datasets (id, name, description) VALUES (%s, %s, %s)",
                (row["id"], row["name"], row["description"]),
            )
    conn.commit()
finally:
    conn.close()

with open("/app/stats.csv", "a", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    for row in rows:
        writer.writerow([row["id"], row["downloads"]])

with open("/tmp/verifier_canary.json", "w", encoding="utf-8") as f:
    json.dump({"common": common, "rows": rows}, f)
os.chmod("/tmp/verifier_canary.json", 0o644)
PY

# Stop whatever currently owns port 8000 before executing the submitted artifact.
kill_port() {
python3 - <<'PY'
import os
import signal
import time

inodes = set()
for path in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(path, "r", encoding="ascii") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F40" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

victims = set()
for pid in os.listdir("/proc"):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                victims.add(int(pid))
                break
    except OSError:
        pass
for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(1)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
}

wait_api() {
python3 - <<'PY'
import time
import requests
for _ in range(30):
    try:
        requests.get("http://127.0.0.1:8000/", timeout=0.4)
        raise SystemExit(0)
    except requests.RequestException:
        time.sleep(0.25)
raise SystemExit(1)
PY
}

if [ "$status" -eq 0 ]; then
    kill_port
    nohup sudo -u user -H bash -c 'cd /home/user && exec python3 /home/user/api.py' >/tmp/submitted_api.log 2>&1 &
    if ! wait_api; then
        # FastAPI submissions commonly expose app but use uvicorn as their launcher.
        kill_port
        nohup sudo -u user -H bash -c 'cd /home/user && exec python3 -m uvicorn api:app --host 127.0.0.1 --port 8000' >>/tmp/submitted_api.log 2>&1 &
        wait_api || status=1
    fi
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import time

import psycopg2
import pytest
import requests
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

API_URL = "http://127.0.0.1:8000/search"

with open("/tmp/verifier_canary.json", "r", encoding="utf-8") as f:
    CANARY = json.load(f)

@pytest.fixture(scope="module", autouse=True)
def wait_for_api():
    """Wait for the API to become available."""
    timeout = 10
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get("http://127.0.0.1:8000/", timeout=1)
            return
        except requests.exceptions.ConnectionError:
            try:
                requests.get(API_URL + "?q=test&limit=1", timeout=1)
                return
            except requests.exceptions.ConnectionError:
                pass
        time.sleep(0.5)
    pytest.fail("API service did not become available on 127.0.0.1:8000 within 10 seconds.")

def expected_results(query, limit):
    conn = psycopg2.connect(dbname="catalog", user="postgres", password="postgres", host="127.0.0.1", port=5432)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name, description FROM datasets")
            datasets = cur.fetchall()
    finally:
        conn.close()

    stats = {}
    with open("/app/stats.csv", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            stats[int(row["dataset_id"])] = int(row["downloads"])

    descriptions = [row[2] for row in datasets]
    vectorizer = TfidfVectorizer(stop_words="english")
    matrix = vectorizer.fit_transform(descriptions)
    query_vector = vectorizer.transform([query])
    similarities = cosine_similarity(query_vector, matrix).ravel()

    expected = []
    for (dataset_id, name, _), similarity in zip(datasets, similarities):
        if dataset_id in stats:
            expected.append({
                "id": dataset_id,
                "name": name,
                "final_score": float(similarity) * math.log10(stats[dataset_id] + 1),
            })
    expected.sort(key=lambda item: item["final_score"], reverse=True)
    return expected[:limit]

def assert_valid_results(data, limit):
    assert "results" in data, "Response JSON must contain a 'results' key."
    results = data["results"]
    assert isinstance(results, list), "'results' must be a list."
    assert len(results) <= limit
    for res in results:
        assert "id" in res, "Result missing 'id' field."
        assert "name" in res, "Result missing 'name' field."
        assert "final_score" in res, "Result missing 'final_score' field."
        assert isinstance(res["final_score"], (int, float)) and not isinstance(res["final_score"], bool)
        assert math.isfinite(res["final_score"])
    return results

def test_search_visual_image_object():
    query = "visual image object"
    response = requests.get(API_URL, params={"q": query, "limit": 2}, timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    results = assert_valid_results(response.json(), 2)
    assert len(results) > 0, "Expected at least 1 result."
    ids = [res["id"] for res in results]
    assert 1 in ids, f"Expected ImageNet (id=1) to be in the top 2 results for query '{query}', but got ids {ids}."

def test_search_machine_learning_survival():
    query = "machine learning predicting survival"
    response = requests.get(API_URL, params={"q": query, "limit": 1}, timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "results" in data, "Response JSON must contain a 'results' key."
    results = data["results"]
    assert len(results) == 1, f"Expected exactly 1 result, got {len(results)}."
    assert results[0]["id"] == 2, f"Expected Titanic (id=2) to be the top result for query '{query}', but got id {results[0]['id']}."

@pytest.mark.parametrize("limit", [1, 2, 4])
def test_live_postgres_csv_tfidf_and_formula(limit):
    query = CANARY["common"]
    expected = expected_results(query, limit)
    response = requests.get(API_URL, params={"q": query, "limit": limit}, timeout=5)
    assert response.status_code == 200, response.text
    actual = assert_valid_results(response.json(), limit)
    assert len(actual) == limit
    assert [r["id"] for r in actual] == [r["id"] for r in expected]
    assert [r["name"] for r in actual] == [r["name"] for r in expected]
    for got, want in zip(actual, expected):
        assert got["final_score"] == pytest.approx(want["final_score"], abs=1.1e-3, rel=1e-4)

@pytest.mark.parametrize("row_index", [0, 2, 3])
def test_unpredictable_unique_description_terms(row_index):
    row = CANARY["rows"][row_index]
    # The second word is unique to this database row and was generated only by the verifier.
    query = row["description"].split()[1]
    expected = expected_results(query, 1)
    response = requests.get(API_URL, params={"q": query, "limit": 1}, timeout=5)
    assert response.status_code == 200, response.text
    actual = assert_valid_results(response.json(), 1)
    assert len(actual) == 1
    assert actual[0]["id"] == row["id"] == expected[0]["id"]
    assert actual[0]["name"] == row["name"] == expected[0]["name"]
    assert actual[0]["final_score"] == pytest.approx(expected[0]["final_score"], abs=1.1e-3, rel=1e-4)

def test_search_logs():
    log_path = "/home/user/search_logs.txt"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\r\n") for line in f]
    assert "visual image object" in lines, "Log file does not contain the first query string."
    assert "machine learning predicting survival" in lines, "Log file does not contain the second query string."
    assert CANARY["common"] in lines, "Log file does not contain the verifier's dynamic query."
    for index in (0, 2, 3):
        assert CANARY["rows"][index]["description"].split()[1] in lines
TEST_EOF

if [ "$status" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
