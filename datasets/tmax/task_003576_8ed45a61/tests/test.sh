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
import random
import sqlite3
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
TOKEN = "secret graph dataset"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}
DB_PATH = "/app/research.db"


def get(path, headers=None):
    try:
        return requests.get(f"{BASE_URL}{path}", headers=headers, timeout=2)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to server: {exc}")


def test_unauthorized_access():
    """Both API endpoints must reject missing and incorrect credentials."""
    paths = ["/api/hindex?author=Alice", "/api/top_papers"]
    for path in paths:
        resp = get(path)
        assert resp.status_code == 401, (
            f"Expected 401 without auth header for {path}, got {resp.status_code}"
        )

        resp = get(path, {"Authorization": "Bearer wrong token"})
        assert resp.status_code == 401, (
            f"Expected 401 with wrong auth header for {path}, got {resp.status_code}"
        )


def test_hindex_alice():
    resp = get("/api/hindex?author=Alice", HEADERS)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert data.get("author") == "Alice", f"Expected author 'Alice', got {data.get('author')}"
    assert data.get("h_index") == 3, f"Expected h_index 3 for Alice, got {data.get('h_index')}"


def test_hindex_bob():
    resp = get("/api/hindex?author=Bob", HEADERS)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert data.get("author") == "Bob", f"Expected author 'Bob', got {data.get('author')}"
    assert data.get("h_index") == 1, f"Expected h_index 1 for Bob, got {data.get('h_index')}"


def test_top_papers():
    resp = get("/api/top_papers", HEADERS)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert isinstance(data, list), f"Expected response to be a list, got {type(data)}"
    assert len(data) == 5, f"Expected 5 top papers, got {len(data)}"

    expected_counts = {
        "Paper A": 5,
        "Paper F": 5,
        "Paper B": 4,
        "Paper C": 3,
        "Paper D": 3,
    }
    for paper in data:
        title = paper.get("title")
        count = paper.get("citation_count")
        assert title in expected_counts, f"Unexpected paper in top 5: {title}"
        assert expected_counts[title] == count, (
            f"Expected {expected_counts[title]} citations for {title}, got {count}"
        )

    counts = [paper.get("citation_count") for paper in data]
    assert counts == sorted(counts, reverse=True), (
        f"Top papers are not sorted by descending citation count: {counts}"
    )


def test_randomized_database_queries():
    """Insert an unpredictable challenge and derive answers directly from SQLite."""
    marker = uuid.uuid4().hex
    h_author = f"Verifier Author {marker}"
    source_author = f"Verifier Sources {marker}"
    top_author = f"Verifier Top Author {marker}"

    conn = sqlite3.connect(DB_PATH, timeout=5)
    inserted_ids = []
    try:
        cur = conn.cursor()
        next_id = cur.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM papers").fetchone()[0]

        # A randomized author challenge whose h-index is not a fixed dataset answer.
        h_paper_count = random.randint(4, 8)
        h_counts = [random.randint(0, h_paper_count + 3) for _ in range(h_paper_count)]
        h_counts[0] = random.randint(1, h_paper_count + 3)
        h_targets = []
        for i in range(h_paper_count):
            pid = next_id
            next_id += 1
            inserted_ids.append(pid)
            h_targets.append((pid, h_counts[i]))
            cur.execute(
                "INSERT INTO papers(id, title, author, year) VALUES (?, ?, ?, ?)",
                (pid, f"Verifier H Paper {marker} {i}", h_author, 2025),
            )

        # Six uniquely ranked high-citation papers force a new, unpredictable top five.
        top_counts = random.sample(range(20, 51), 6)
        top_targets = []
        for i, count in enumerate(top_counts):
            pid = next_id
            next_id += 1
            inserted_ids.append(pid)
            title = f"Verifier Top Paper {marker} {i}"
            top_targets.append((pid, count))
            cur.execute(
                "INSERT INTO papers(id, title, author, year) VALUES (?, ?, ?, ?)",
                (pid, title, top_author, 2025),
            )

        source_count = max(max(h_counts), max(top_counts))
        source_ids = []
        for i in range(source_count):
            pid = next_id
            next_id += 1
            inserted_ids.append(pid)
            source_ids.append(pid)
            cur.execute(
                "INSERT INTO papers(id, title, author, year) VALUES (?, ?, ?, ?)",
                (pid, f"Verifier Source {marker} {i}", source_author, 2025),
            )

        for target_id, count in h_targets + top_targets:
            cur.executemany(
                "INSERT INTO citations(source_id, target_id) VALUES (?, ?)",
                [(source_ids[i], target_id) for i in range(count)],
            )
        conn.commit()

        # Derive the h-index through a full table scan, independent of the API result.
        rows = cur.execute(
            """
            SELECT p.id, COUNT(c.target_id)
            FROM papers AS p
            LEFT JOIN citations AS c NOT INDEXED ON c.target_id = p.id
            WHERE p.author = ?
            GROUP BY p.id
            """,
            (h_author,),
        ).fetchall()
        citation_counts = sorted((row[1] for row in rows), reverse=True)
        expected_h = sum(count >= rank for rank, count in enumerate(citation_counts, 1))

        resp = get("/api/hindex", HEADERS | {}) if False else None
        try:
            resp = requests.get(
                f"{BASE_URL}/api/hindex",
                params={"author": h_author},
                headers=HEADERS,
                timeout=2,
            )
        except requests.RequestException as exc:
            pytest.fail(f"Failed to connect to server: {exc}")
        assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {resp.text}")
        assert data.get("author") == h_author
        assert data.get("h_index") == expected_h, (
            f"Expected randomized h-index {expected_h}, got {data.get('h_index')}"
        )

        expected_top = cur.execute(
            """
            SELECT p.title, COUNT(c.target_id) AS citation_count
            FROM papers AS p
            LEFT JOIN citations AS c NOT INDEXED ON c.target_id = p.id
            GROUP BY p.id
            ORDER BY citation_count DESC, p.id ASC
            LIMIT 5
            """
        ).fetchall()

        resp = get("/api/top_papers", HEADERS)
        assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {resp.text}")
        assert isinstance(data, list), f"Expected response to be a list, got {type(data)}"
        assert len(data) == 5, f"Expected 5 top papers, got {len(data)}"

        actual_top = [(item.get("title"), item.get("citation_count")) for item in data]
        assert actual_top == expected_top, (
            f"Top papers do not match database-derived ranking. "
            f"Expected {expected_top}, got {actual_top}"
        )
        actual_counts = [count for _, count in actual_top]
        assert actual_counts == sorted(actual_counts, reverse=True), (
            f"Top papers are not sorted descending: {actual_counts}"
        )
    finally:
        try:
            if inserted_ids:
                placeholders = ",".join("?" for _ in inserted_ids)
                conn.execute(
                    f"DELETE FROM citations WHERE source_id IN ({placeholders}) OR target_id IN ({placeholders})",
                    inserted_ids + inserted_ids,
                )
                conn.execute(f"DELETE FROM papers WHERE id IN ({placeholders})", inserted_ids)
                conn.commit()
        finally:
            conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
