#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import subprocess
import time
import uuid

import psycopg2
import pytest

SCRIPT_PATH = "/home/user/query_filter.py"
DB_ARGS = dict(
    dbname="research_db",
    user="researcher",
    password="password",
    host="127.0.0.1",
    port=5432,
)


def run_script_on_file(script_path, file_path):
    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", script_path, file_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as exc:
        return str(exc)


def explain(sql_text):
    with psycopg2.connect(**DB_ARGS) as conn:
        with conn.cursor() as cur:
            cur.execute("EXPLAIN (FORMAT JSON) " + sql_text)
            value = cur.fetchone()[0]
    if isinstance(value, str):
        value = json.loads(value)
    return value[0]["Plan"]


def has_forbidden_seq_scan(node):
    if (
        node.get("Node Type") == "Seq Scan"
        and node.get("Relation Name") in {"papers", "citations"}
    ):
        return True
    return any(has_forbidden_seq_scan(child) for child in node.get("Plans", []))


def expected_result(sql_text):
    plan = explain(sql_text)
    if has_forbidden_seq_scan(plan) or float(plan["Total Cost"]) > 50000:
        return "REJECT"
    return "ACCEPT"


def write_hidden_query(sql_text):
    path = f"/tmp/hidden_query_{uuid.uuid4().hex}.sql"
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(sql_text)
    os.chmod(path, 0o644)
    return path


def test_query_filter_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Not a file: {SCRIPT_PATH}"


def test_required_indexes_were_created():
    with psycopg2.connect(**DB_ARGS) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT t.relname,
                       array_agg(a.attname ORDER BY keys.ordinality)
                           FILTER (WHERE keys.ordinality <= i.indnkeyatts) AS key_columns
                FROM pg_index i
                JOIN pg_class t ON t.oid = i.indrelid
                CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS keys(attnum, ordinality)
                JOIN pg_attribute a
                  ON a.attrelid = i.indrelid AND a.attnum = keys.attnum
                WHERE t.relname IN ('papers', 'citations')
                  AND i.indisvalid AND i.indisready
                  AND i.indpred IS NULL
                GROUP BY i.indexrelid, t.relname, i.indnkeyatts
                """
            )
            indexes = cur.fetchall()

    citation_keys = [cols for table, cols in indexes if table == "citations"]
    paper_keys = [cols for table, cols in indexes if table == "papers"]

    assert any(cols and cols[0] == "paper_id" for cols in citation_keys), \
        "Missing an index led by citations.paper_id for recursive citation traversal"
    assert any(cols[:3] == ["domain_id", "published_year", "citation_count"] for cols in paper_keys), \
        "Missing a papers index led by (domain_id, published_year, citation_count)"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*.sql"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.sql"))

    assert clean_files, f"No clean corpus files found in {clean_dir}"
    assert evil_files, f"No evil corpus files found in {evil_dir}"

    evil_bypassed = []
    clean_modified = []
    for file_path in evil_files:
        output = run_script_on_file(SCRIPT_PATH, file_path)
        if "REJECT" not in output or "ACCEPT" in output:
            evil_bypassed.append(os.path.basename(file_path))
    for file_path in clean_files:
        output = run_script_on_file(SCRIPT_PATH, file_path)
        if "ACCEPT" not in output or "REJECT" in output:
            clean_modified.append(os.path.basename(file_path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_hidden_queries_match_actual_plans():
    marker = uuid.uuid4().hex
    point_id = random.randint(1, 100000)
    hidden_queries = [
        f"SELECT id FROM papers WHERE id = {point_id} /* {marker}_point */;",
        f"SELECT id FROM papers WHERE title = 'not-present-{marker}' /* {marker}_scan */;",
    ]

    # Derive a query whose top-level cost exceeds the threshold in this database,
    # rather than trusting a fixed query or a hard-coded expected plan.
    rows = 1_000_000
    while True:
        candidate = f"SELECT * FROM generate_series(1, {rows}) /* {marker}_cost */;"
        plan = explain(candidate)
        if float(plan["Total Cost"]) > 50000 and not has_forbidden_seq_scan(plan):
            hidden_queries.append(candidate)
            break
        rows *= 2
        assert rows <= 100_000_000, "Could not construct a high-cost hidden query"

    for sql_text in hidden_queries:
        expected = expected_result(sql_text)
        path = write_hidden_query(sql_text)
        try:
            output = run_script_on_file(SCRIPT_PATH, path)
        finally:
            os.unlink(path)
        assert output == expected, f"Expected {expected} from the actual JSON plan, got {output!r}"


def _log_snapshot():
    return {path: os.path.getsize(path) for path in glob.glob("/var/log/postgresql/*.log")}


def _new_log_text(snapshot):
    chunks = []
    for path in glob.glob("/var/log/postgresql/*.log"):
        start = snapshot.get(path, 0)
        size = os.path.getsize(path)
        if size < start:
            start = 0
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            handle.seek(start)
            chunks.append(handle.read())
    return "\n".join(chunks)


def test_script_really_sends_explain_format_json_to_postgresql():
    nonce = "validator_probe_" + uuid.uuid4().hex
    sql_text = f"SELECT id FROM papers WHERE id = {random.randint(1, 100000)} /* {nonce} */;"
    path = write_hidden_query(sql_text)

    admin = psycopg2.connect(dbname="research_db", user="postgres")
    admin.autocommit = True
    try:
        with admin.cursor() as cur:
            cur.execute("ALTER ROLE researcher SET log_statement TO 'all'")
        snapshot = _log_snapshot()
        output = run_script_on_file(SCRIPT_PATH, path)
        time.sleep(0.5)
    finally:
        try:
            with admin.cursor() as cur:
                cur.execute("ALTER ROLE researcher RESET log_statement")
        finally:
            admin.close()
            os.unlink(path)

    assert output == "ACCEPT", f"Probe query should be accepted, got {output!r}"
    logged = _new_log_text(snapshot)
    matching_lines = "\n".join(line for line in logged.splitlines() if nonce in line)
    assert matching_lines, "The validator did not send the probe query to PostgreSQL"
    assert re.search(r"EXPLAIN\s*\([^)]*FORMAT\s+JSON", matching_lines, re.IGNORECASE), \
        "The validator did not request EXPLAIN (FORMAT JSON) for the supplied query"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
