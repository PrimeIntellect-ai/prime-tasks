#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import time
import urllib.request
from collections import Counter, defaultdict

import pytest
from neo4j import GraphDatabase

SCRIPT_PATH = "/home/user/etl_pipeline.py"
OUTPUT_PATH = "/home/user/top_users.json"
BOLT_URI = "bolt://127.0.0.1:7687"
API_URI = "http://127.0.0.1:8080/stream"


def index_rows(session):
    return [dict(record) for record in session.run("SHOW INDEX INFO")]


def has_user_id_index(rows):
    for row in rows:
        values = {str(value).lower() for value in row.values() if value is not None}
        if "user" in values and "id" in values:
            return True
    return False


def test_etl_execution_time_and_output():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    with open(SCRIPT_PATH, "r", encoding="utf-8") as source_file:
        source = source_file.read()

    # Inspect Python string literals, excluding comments, for the required bulk-load
    # and graph-analytics Cypher constructs.
    tree = ast.parse(source, filename=SCRIPT_PATH)
    string_literals = [
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    ]
    cypher_text = "\n".join(string_literals).upper()
    assert "UNWIND" in cypher_text, "The ETL script does not contain an UNWIND bulk-insert query."
    for token in ("MATCH", "FOLLOWS", "COUNT", "ORDER BY", "LIMIT"):
        assert token in cypher_text, f"The script's analytics query is missing {token}."

    with urllib.request.urlopen(API_URI, timeout=10) as response:
        events = json.loads(response.read())

    assert isinstance(events, list) and len(events) == 50000
    expected_edges = {(event["src"], event["dst"]) for event in events}
    expected_users = {event["src"] for event in events} | {event["dst"] for event in events}
    expected_degrees = defaultdict(int)
    for src, dst in expected_edges:
        expected_degrees[src] += 1

    driver = GraphDatabase.driver(BOLT_URI)
    try:
        with driver.session() as session:
            # Establish a clean graph and remove the required index so this run must
            # create both the schema and data itself.
            session.run("MATCH (n) DETACH DELETE n").consume()
            if has_user_id_index(index_rows(session)):
                session.run("DROP INDEX ON :User(id)").consume()
            assert not has_user_id_index(index_rows(session)), "Could not remove pre-existing User(id) index."

        # Remove output file if it exists to ensure we are testing the new run.
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        start_time = time.time()
        result = subprocess.run(
            ["python3", SCRIPT_PATH], capture_output=True, text=True, timeout=15
        )
        duration = time.time() - start_time

        assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"
        assert duration <= 3.0, f"Execution took {duration:.2f}s, threshold is 3.0s"

        assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"

        with open(OUTPUT_PATH, "r") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")

        assert isinstance(data, list), "Output JSON should be a list of objects."
        assert len(data) == 5, f"Expected exactly 5 users in output, got {len(data)}."

        for idx, item in enumerate(data):
            assert isinstance(item, dict), f"Item at index {idx} is not a dictionary."
            assert "user" in item, f"Item at index {idx} missing 'user' key."
            assert "out_degree" in item, f"Item at index {idx} missing 'out_degree' key."
            assert isinstance(item["user"], str), f"'user' at index {idx} should be a string."
            assert isinstance(item["out_degree"], int), f"'out_degree' at index {idx} should be an integer."

        out_degrees = [item["out_degree"] for item in data]
        assert out_degrees == sorted(out_degrees, reverse=True), "The users are not sorted by out_degree in descending order."

        with driver.session() as session:
            assert has_user_id_index(index_rows(session)), "Missing index on :User(id)."

            actual_users = {
                record["id"]
                for record in session.run("MATCH (u:User) RETURN u.id AS id")
            }
            assert actual_users == expected_users, "Memgraph does not contain exactly the API users."

            relationship_types = {
                record["kind"]: record["amount"]
                for record in session.run(
                    "MATCH ()-[r]->() RETURN type(r) AS kind, count(r) AS amount"
                )
            }
            assert relationship_types == {"FOLLOWS": len(expected_edges)}, \
                "Memgraph does not contain exactly the expected FOLLOWS relationships."

            actual_edges = Counter()
            for record in session.run(
                "MATCH (s:User)-[r:FOLLOWS]->(d:User) "
                "RETURN s.id AS src, d.id AS dst, count(r) AS amount"
            ):
                actual_edges[(record["src"], record["dst"])] = record["amount"]

            assert set(actual_edges) == expected_edges, "Loaded graph edges differ from the API data."
            assert all(amount == 1 for amount in actual_edges.values()), \
                "Duplicate API pairs were not preserved with the original MERGE semantics."

        # Validate output against answers independently derived from the API.
        selected_users = [item["user"] for item in data]
        assert len(set(selected_users)) == 5, "Top-five output contains duplicate users."
        for item in data:
            assert item["user"] in expected_degrees, f"Unknown user in output: {item['user']}"
            assert item["out_degree"] == expected_degrees[item["user"]], \
                f"Incorrect out-degree for {item['user']}."

        ranked_degrees = sorted(expected_degrees.values(), reverse=True)
        cutoff = ranked_degrees[4]
        mandatory = {user for user, degree in expected_degrees.items() if degree > cutoff}
        assert mandatory.issubset(set(selected_users)), "A user above the top-five cutoff was omitted."
        assert all(expected_degrees[user] >= cutoff for user in selected_users), \
            "Output includes a user below the top-five cutoff."
    finally:
        driver.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
