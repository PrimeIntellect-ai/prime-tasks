#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import stat
import subprocess

import jsonschema
import pytest

HOME = "/home/user"
DB_PATH = f"{HOME}/kuzu_db"
INIT_PATH = f"{HOME}/init_graph.py"
QUERY_PATH = f"{HOME}/query.cypher"
EXEC_PATH = f"{HOME}/execute_and_validate.sh"
OUTPUT_PATH = f"{HOME}/output.json"
SCHEMA_PATH = f"{HOME}/schema.json"
NODES_PATH = f"{HOME}/data/nodes.csv"
EDGES_PATH = f"{HOME}/data/edges.csv"


def run_artifact(command, timeout=90):
    result = subprocess.run(
        command,
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def rebuild_and_execute():
    shutil.rmtree(DB_PATH, ignore_errors=True)
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_artifact(["python3", INIT_PATH])
    assert os.path.isdir(DB_PATH), "init_graph.py did not create /home/user/kuzu_db"
    run_artifact([EXEC_PATH])


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(INIT_PATH), "/home/user/init_graph.py is missing."
    assert os.path.isfile(QUERY_PATH), "/home/user/query.cypher is missing."
    assert os.path.isfile(EXEC_PATH), "/home/user/execute_and_validate.sh is missing."
    rebuild_and_execute()


def load_json():
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is missing. Did the bash script run successfully?"
    with open(OUTPUT_PATH) as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_PATH} does not contain valid JSON.")


def expected_from_csv():
    with open(NODES_PATH, newline="") as f:
        nodes = list(csv.DictReader(f))
    with open(EDGES_PATH, newline="") as f:
        edges = list(csv.DictReader(f))

    names = {int(row["id"]): row["name"] for row in nodes}
    alice_ids = [node_id for node_id, name in names.items() if name == "Alice"]
    outgoing = {}
    for row in edges:
        outgoing.setdefault(int(row["src"]), []).append(
            (int(row["dst"]), float(row["weight"]))
        )

    results = []
    for alice_id in alice_ids:
        for middle, first_weight in outgoing.get(alice_id, []):
            if first_weight <= 0.5:
                continue
            for destination, second_weight in outgoing.get(middle, []):
                if second_weight > 0.5:
                    results.append({
                        "target_name": names[destination],
                        "total_weight": first_weight + second_weight,
                    })
    results.sort(key=lambda row: (-row["total_weight"], row["target_name"]))
    return results[:5]


def assert_rows(actual, expected):
    assert isinstance(actual, list), "Output JSON must be a list of objects."
    assert len(actual) == len(expected), f"Expected {len(expected)} results, got {len(actual)}."
    for i, wanted in enumerate(expected):
        assert actual[i].get("target_name") == wanted["target_name"], (
            f"Result {i} target_name mismatch. Expected {wanted['target_name']}, "
            f"got {actual[i].get('target_name')}"
        )
        assert actual[i].get("total_weight") == pytest.approx(
            wanted["total_weight"], rel=1e-5
        ), (
            f"Result {i} total_weight mismatch. Expected {wanted['total_weight']}, "
            f"got {actual[i].get('total_weight')}"
        )


# Preserve the original assertions.
def test_init_graph_script_exists():
    assert os.path.isfile(INIT_PATH), "/home/user/init_graph.py is missing."


def test_kuzu_db_directory_exists():
    assert os.path.isdir(DB_PATH), "/home/user/kuzu_db directory is missing. Did the init script run?"


def test_query_cypher_exists():
    assert os.path.isfile(QUERY_PATH), "/home/user/query.cypher is missing."


def test_bash_script_exists_and_executable():
    assert os.path.isfile(EXEC_PATH), f"{EXEC_PATH} is missing."
    st = os.stat(EXEC_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{EXEC_PATH} is not executable."


def test_output_json_correctness():
    data = load_json()
    expected_data = [
        {"target_name": "Eve", "total_weight": 1.7},
        {"target_name": "Frank", "total_weight": 1.7},
        {"target_name": "Diana", "total_weight": 1.3},
    ]
    assert_rows(data, expected_data)


def test_output_conforms_to_provided_schema():
    with open(SCHEMA_PATH) as f:
        schema = json.load(f)
    jsonschema.validate(load_json(), schema)


def test_init_uses_kuzu_copy_and_database_contains_source_data():
    with open(INIT_PATH) as f:
        source = f.read()
    assert len(re.findall(r"\bCOPY\b", source, flags=re.IGNORECASE)) >= 2, (
        "init_graph.py must use Kuzu COPY commands for both CSV files."
    )

    import kuzu
    database = kuzu.Database(DB_PATH)
    connection = kuzu.Connection(database)

    def collect(query):
        result = connection.execute(query)
        rows = []
        while result.has_next():
            rows.append(result.get_next())
        return rows

    with open(NODES_PATH, newline="") as f:
        expected_nodes = sorted(
            [(int(r["id"]), r["name"], r["department"]) for r in csv.DictReader(f)]
        )
    actual_nodes = collect(
        "MATCH (p:Person) RETURN p.id, p.name, p.department ORDER BY p.id"
    )
    assert actual_nodes == [list(row) for row in expected_nodes]

    with open(EDGES_PATH, newline="") as f:
        expected_edges = sorted(
            [
                (int(r["src"]), int(r["dst"]), r["relationship"], float(r["weight"]))
                for r in csv.DictReader(f)
            ]
        )
    actual_edges = collect(
        "MATCH (a:Person)-[r:CommunicatesWith]->(b:Person) "
        "RETURN a.id, b.id, r.relationship, r.weight ORDER BY a.id, b.id"
    )
    assert len(actual_edges) == len(expected_edges)
    for actual, expected in zip(actual_edges, expected_edges):
        assert actual[:3] == list(expected[:3])
        assert actual[3] == pytest.approx(expected[3])


def test_execution_uses_query_and_schema_cli_and_handles_changed_input():
    with open(EDGES_PATH, "rb") as f:
        original_edges = f.read()
    with open(QUERY_PATH, "rb") as f:
        original_query = f.read()
    with open(SCHEMA_PATH, "rb") as f:
        original_schema = f.read()

    with open(EXEC_PATH) as f:
        execute_source = f.read()
    assert re.search(r"\bjsonschema\b", execute_source), (
        "execute_and_validate.sh must invoke the jsonschema CLI."
    )

    try:
        with open(EDGES_PATH, newline="") as f:
            rows = list(csv.DictReader(f))
            fieldnames = rows[0].keys()
        changed_weights = {
            ("1", "2"): "0.65",
            ("1", "3"): "0.55",
            ("2", "4"): "0.80",
            ("3", "5"): "0.95",
            ("1", "5"): "0.70",
            ("5", "6"): "0.60",
        }
        for row in rows:
            key = (row["src"], row["dst"])
            if key in changed_weights:
                row["weight"] = changed_weights[key]
        with open(EDGES_PATH, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

        rebuild_and_execute()
        expected = expected_from_csv()
        assert expected != [
            {"target_name": "Eve", "total_weight": 1.7},
            {"target_name": "Frank", "total_weight": 1.7},
            {"target_name": "Diana", "total_weight": 1.3},
        ], "The changed-data test must differ from the fixed example."
        assert_rows(load_json(), expected)

        # A script that ignores query.cypher must not pass.
        with open(QUERY_PATH, "w") as f:
            f.write("THIS IS NOT VALID CYPHER")
        invalid_query_run = subprocess.run(
            [EXEC_PATH], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=90
        )
        assert invalid_query_run.returncode != 0, (
            "execute_and_validate.sh succeeded with an invalid query.cypher; "
            "it must read and execute that file against Kuzu."
        )
        with open(QUERY_PATH, "wb") as f:
            f.write(original_query)

        # A script that omits schema validation must not pass.
        with open(SCHEMA_PATH, "w") as f:
            json.dump({"not": {}}, f)
        invalid_schema_run = subprocess.run(
            [EXEC_PATH], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=90
        )
        assert invalid_schema_run.returncode != 0, (
            "execute_and_validate.sh succeeded when schema.json rejected every value."
        )
    finally:
        with open(EDGES_PATH, "wb") as f:
            f.write(original_edges)
        with open(QUERY_PATH, "wb") as f:
            f.write(original_query)
        with open(SCHEMA_PATH, "wb") as f:
            f.write(original_schema)
        shutil.rmtree(DB_PATH, ignore_errors=True)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        subprocess.run(["python3", INIT_PATH], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run([EXEC_PATH], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
