#!/bin/bash
set +e
mkdir -p /logs/verifier

TRACE_FILE="/tmp/relevance_scorer_trace.$$.bin"
REAL_SCORER="/app/relevance_scorer.verifier-real"
SCORER_READY=1

: > "$TRACE_FILE" || SCORER_READY=0
chmod 666 "$TRACE_FILE" 2>/dev/null || SCORER_READY=0

if [ "$SCORER_READY" -eq 1 ] && [ -x /app/relevance_scorer ]; then
    mv /app/relevance_scorer "$REAL_SCORER" || SCORER_READY=0
else
    SCORER_READY=0
fi

if [ "$SCORER_READY" -eq 1 ]; then
    cat > /app/relevance_scorer <<EOF
#!/bin/sh
printf '%s\\0' "\$1" >> "$TRACE_FILE"
exec "$REAL_SCORER" "\$@"
EOF
    chmod 755 /app/relevance_scorer || SCORER_READY=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import sqlite3
import subprocess
import uuid
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
ENDPOINT = f"{BASE_URL}/api/search"
VALID_TOKEN = "astro-query-2024"
HEADERS = {"X-Research-Token": VALID_TOKEN}
TRACE_FILE = os.environ["VERIFIER_SCORER_TRACE"]
REAL_SCORER = os.environ["VERIFIER_REAL_SCORER"]


def test_missing_auth():
    payload = {"category": "pulsar", "min_score": 0.0, "page": 1, "limit": 10}
    try:
        response = requests.post(ENDPOINT, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for missing token, got {response.status_code}"


def test_invalid_auth():
    payload = {"category": "pulsar", "min_score": 0.0, "page": 1, "limit": 10}
    headers = {"X-Research-Token": "wrong-token"}
    response = requests.post(ENDPOINT, json=payload, headers=headers, timeout=5)
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid token, got {response.status_code}"


def test_valid_query_pulsar():
    payload = {"category": "pulsar", "min_score": 0.0, "page": 1, "limit": 10}
    response = requests.post(ENDPOINT, json=payload, headers=HEADERS, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"

    data = response.json()
    assert data["page"] == 1
    assert data["limit"] == 10
    assert data["total_filtered_results"] == 2

    results = data["results"]
    assert len(results) == 2

    # Check sorting: score DESC
    assert results[0]["id"] == "obs_002"
    assert results[0]["score"] == 31.5
    assert results[1]["id"] == "obs_001"
    assert results[1]["score"] == 27.75


def test_pagination():
    payload = {"category": "pulsar", "min_score": 0.0, "page": 2, "limit": 1}
    response = requests.post(ENDPOINT, json=payload, headers=HEADERS, timeout=5)
    assert response.status_code == 200

    data = response.json()
    assert data["page"] == 2
    assert data["limit"] == 1
    assert data["total_filtered_results"] == 2

    results = data["results"]
    assert len(results) == 1
    assert results[0]["id"] == "obs_001"


def test_filtering_min_score():
    payload = {"category": "pulsar", "min_score": 30.0, "page": 1, "limit": 10}
    response = requests.post(ENDPOINT, json=payload, headers=HEADERS, timeout=5)
    assert response.status_code == 200

    data = response.json()
    assert data["total_filtered_results"] == 1
    assert len(data["results"]) == 1
    assert data["results"][0]["id"] == "obs_002"


def test_sql_injection_prevention():
    # If parameterized queries are used, this should return 0 results (no category matches the literal string)
    payload = {"category": "pulsar' OR 1=1 --", "min_score": 0.0, "page": 1, "limit": 10}
    response = requests.post(ENDPOINT, json=payload, headers=HEADERS, timeout=5)

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    data = response.json()
    assert data["total_filtered_results"] == 0, "SQL injection succeeded! Parameterized queries were not used correctly."
    assert len(data["results"]) == 0


def scorer_score(merged):
    output = subprocess.check_output(
        [REAL_SCORER, json.dumps(merged, separators=(",", ":"))],
        text=True,
        timeout=5,
    )
    return float(output.strip())


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def assert_exact_response(response, page, limit, expected_all, expected_page):
    assert response.status_code == 200, response.text
    assert response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() == "application/json"
    data = response.json()
    assert set(data) == {"page", "limit", "total_filtered_results", "results"}
    assert type(data["page"]) is int and data["page"] == page
    assert type(data["limit"]) is int and data["limit"] == limit
    assert type(data["total_filtered_results"]) is int
    assert data["total_filtered_results"] == len(expected_all)
    assert type(data["results"]) is list
    assert len(data["results"]) == len(expected_page)

    for actual, expected in zip(data["results"], expected_page):
        assert set(actual) == {"id", "score", "merged_record"}
        assert actual["id"] == expected["id"]
        assert type(actual["score"]) is float
        assert actual["score"] == pytest.approx(expected["score"], rel=0, abs=1e-6)
        assert actual["merged_record"] == expected["merged_record"]
        assert set(actual["merged_record"]) == {"id", "category", "timestamp", "doc_data"}


def test_runtime_records_full_merge_scorer_ties_filtering_and_pagination():
    nonce = uuid.uuid4().hex
    # The quote and SQL-looking suffix ensure this unpredictable category is treated literally.
    category = f"runtime_{nonce}' OR 1=1 --"
    ids = [f"rt_{nonce}_z", f"rt_{nonce}_b", f"rt_{nonce}_a", f"rt_{nonce}_low"]
    rows = [
        (ids[0], category, "2042-04-01T01:02:03Z", {"mass": 20.0, "spectral_class": "Q", "marker": nonce + "-high"}),
        (ids[1], category, "2042-04-02T01:02:03Z", {"mass": 10.0, "spectral_class": "AA", "marker": nonce + "-tie-b"}),
        (ids[2], category, "2042-04-03T01:02:03Z", {"mass": 10.0, "spectral_class": "BB", "marker": nonce + "-tie-a", "nested": {"v": 7}}),
        (ids[3], category, "2042-04-04T01:02:03Z", {"mass": 2.0, "spectral_class": "XYZ", "marker": nonce + "-low"}),
    ]
    decoy_id = f"rt_{nonce}_decoy"
    decoy = (decoy_id, category + "_different", "2042-05-01T00:00:00Z", {"mass": 999.0, "spectral_class": "X", "marker": "must-not-appear"})
    all_rows = rows + [decoy]
    doc_paths = []

    connection = sqlite3.connect("/home/user/data/catalog.db")
    try:
        connection.executemany(
            "INSERT INTO Observations(id, category, timestamp) VALUES (?, ?, ?)",
            [(record_id, cat, timestamp) for record_id, cat, timestamp, _ in all_rows],
        )
        connection.commit()
        for record_id, _, _, document in all_rows:
            path = Path("/home/user/data/docs") / f"{record_id}.json"
            path.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
            doc_paths.append(path)

        expected = []
        for record_id, cat, timestamp, document in rows:
            merged = {"id": record_id, "category": cat, "timestamp": timestamp, "doc_data": document}
            expected.append({"id": record_id, "score": scorer_score(merged), "merged_record": merged})
        expected.sort(key=lambda item: (-item["score"], item["id"]))

        # Clear baseline calls so this request must account for every newly inserted record.
        Path(TRACE_FILE).write_bytes(b"")
        response = requests.post(
            ENDPOINT,
            json={"category": category, "min_score": -1000000.0, "page": 1, "limit": 50},
            headers=HEADERS,
            timeout=10,
        )
        assert_exact_response(response, 1, 50, expected, expected)

        traced_raw = [part for part in Path(TRACE_FILE).read_bytes().split(b"\0") if part]
        traced = []
        for raw in traced_raw:
            try:
                traced.append(json.loads(raw.decode("utf-8")))
            except Exception as exc:
                pytest.fail(f"Scorer was invoked with a non-JSON merged record: {exc}")
        traced_counts = collections.Counter(canonical(value) for value in traced)
        for item in expected:
            assert traced_counts[canonical(item["merged_record"])] >= 1, (
                f"/app/relevance_scorer was not invoked for {item['id']} with the exact merged record"
            )

        tie_score = next(item["score"] for item in expected if item["id"] == ids[1])
        filtered = [item for item in expected if item["score"] >= tie_score]
        # A score exactly equal to min_score must remain, and tied IDs must be alphabetical.
        assert [item["id"] for item in filtered if item["score"] == tie_score] == sorted([ids[1], ids[2]])
        page_two = filtered[1:2]
        response = requests.post(
            ENDPOINT,
            json={"category": category, "min_score": tie_score, "page": 2, "limit": 1},
            headers=HEADERS,
            timeout=10,
        )
        assert_exact_response(response, 2, 1, filtered, page_two)
    finally:
        connection.execute(
            "DELETE FROM Observations WHERE id IN (%s)" % ",".join("?" for _ in all_rows),
            [row[0] for row in all_rows],
        )
        connection.commit()
        connection.close()
        for path in doc_paths:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
TEST_EOF

if [ "$SCORER_READY" -eq 1 ]; then
    VERIFIER_SCORER_TRACE="$TRACE_FILE" VERIFIER_REAL_SCORER="$REAL_SCORER" \
        python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
    TEST_STATUS=$?
else
    echo "Failed to instrument /app/relevance_scorer"
    TEST_STATUS=1
fi

if [ -e "$REAL_SCORER" ]; then
    rm -f /app/relevance_scorer
    mv "$REAL_SCORER" /app/relevance_scorer
fi
rm -f "$TRACE_FILE"

if [ "$TEST_STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
