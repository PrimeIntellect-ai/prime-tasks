#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import heapq
import json
import os
import stat
import subprocess
import uuid

import pytest
from jsonschema import validate
from rdflib import Graph, Namespace, RDF

SCRIPT_PATH = "/home/user/backup_router.py"
OUTPUT_PATH = "/home/user/backup_routing_plan.json"
TTL_PATH = "/home/user/infrastructure.ttl"
SCHEMA_PATH = "/home/user/output_schema.json"
EX = Namespace("http://example.org/infra#")


def run_router():
    return subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


@pytest.fixture(scope="module", autouse=True)
def execute_submission_on_original_input():
    assert os.path.lexists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert not os.path.islink(SCRIPT_PATH), "backup_router.py must be a regular Python source file, not a symlink."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "backup_router.py must be a regular file."
    assert os.path.getsize(SCRIPT_PATH) > 0, "backup_router.py is empty."

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"backup_router.py is not valid Python: {exc}")

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(isinstance(c.func, ast.Attribute) and c.func.attr == "query" for c in calls), \
        "backup_router.py must execute an rdflib SPARQL query."
    string_literals = "\n".join(
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    ).upper()
    assert "SELECT" in string_literals, "No SPARQL SELECT query was found in backup_router.py."
    assert "NEEDBACKUP" in string_literals and "STORAGENODE" in string_literals and "NETWORKLINK" in string_literals, \
        "SPARQL queries must extract backup databases, storage nodes, and network links."
    assert "JSONSCHEMA" in source.upper(), "backup_router.py must use jsonschema for output validation."
    assert any(isinstance(c.func, ast.Attribute) and c.func.attr == "validate" or
               isinstance(c.func, ast.Name) and c.func.id == "validate" for c in calls), \
        "backup_router.py must call a JSON schema validation method."

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = run_router()
    assert result.returncode == 0, \
        f"backup_router.py failed on the supplied infrastructure:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def load_output():
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def test_output_file_exists():
    """Test that the output JSON file was created."""
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. Did the script run successfully?"


def test_output_format_and_sorting():
    """Test that the output is a JSON array and sorted by database_id."""
    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")

    assert isinstance(data, list), "Output must be a JSON array."
    assert len(data) == 2, f"Output should contain exactly 2 databases (DB1 and DB3) that need backup, but found {len(data)}."

    db_ids = [item.get("database_id") for item in data]
    assert db_ids == sorted(db_ids), "Output array must be sorted in ascending alphabetical order by database_id."


def test_output_routing_logic():
    """Test the correctness of the routing logic for each database."""
    with open(OUTPUT_PATH, 'r') as f:
        data = json.load(f)

    db_map = {item.get("database_id"): item for item in data}

    db1_id = "http://example.org/infra#DB1"
    db3_id = "http://example.org/infra#DB3"

    assert db1_id in db_map, f"Missing routing result for {db1_id}. Is the SPARQL query finding all databases needing backup?"
    assert db3_id in db_map, f"Missing routing result for {db3_id}. Is the SPARQL query finding all databases needing backup?"

    db1_res = db_map[db1_id]
    assert db1_res.get("target_storage_id") == "http://example.org/infra#Storage1", "DB1 should be routed to Storage1 (lowest latency)."
    assert db1_res.get("total_latency") == 25, f"DB1 total latency should be 25, got {db1_res.get('total_latency')}."
    assert db1_res.get("path") == [
        "http://example.org/infra#DB1",
        "http://example.org/infra#Switch1",
        "http://example.org/infra#Storage1"
    ], "DB1 path is incorrect. Check bidirectional link traversal."

    db3_res = db_map[db3_id]
    assert db3_res.get("target_storage_id") == "http://example.org/infra#Storage2", "DB3 should be routed to Storage2. Storage1 does not have enough capacity."
    assert db3_res.get("total_latency") == 42, f"DB3 total latency should be 42, got {db3_res.get('total_latency')}."
    assert db3_res.get("path") == [
        "http://example.org/infra#DB3",
        "http://example.org/infra#Switch2",
        "http://example.org/infra#Storage2"
    ], "DB3 path is incorrect. Check capacity constraints and bidirectional link traversal."


def execute_with_files(ttl_text, schema_obj):
    with open(TTL_PATH, "rb") as f:
        old_ttl = f.read()
    with open(SCHEMA_PATH, "rb") as f:
        old_schema = f.read()
    had_output = os.path.exists(OUTPUT_PATH)
    old_output = None
    if had_output:
        with open(OUTPUT_PATH, "rb") as f:
            old_output = f.read()

    try:
        with open(TTL_PATH, "w", encoding="utf-8") as f:
            f.write(ttl_text)
        with open(SCHEMA_PATH, "w", encoding="utf-8") as f:
            json.dump(schema_obj, f)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        result = run_router()
        produced = None
        if os.path.exists(OUTPUT_PATH):
            with open(OUTPUT_PATH, "rb") as f:
                produced = f.read()
        return result, produced
    finally:
        with open(TTL_PATH, "wb") as f:
            f.write(old_ttl)
        with open(SCHEMA_PATH, "wb") as f:
            f.write(old_schema)
        if had_output:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(old_output)
        elif os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)


def derive_expected(ttl_text):
    graph = Graph()
    graph.parse(data=ttl_text, format="turtle")

    capacities = {
        node: int(capacity)
        for node, capacity in graph.subject_objects(EX.availableCapacity)
        if (node, RDF.type, EX.StorageNode) in graph
    }
    databases = []
    for node in graph.subjects(RDF.type, EX.Database):
        needs = graph.value(node, EX.needsBackup)
        if needs is not None and bool(needs.toPython()):
            databases.append((node, int(graph.value(node, EX.dbSize))))

    adjacency = {}
    for link in graph.subjects(RDF.type, EX.NetworkLink):
        source = graph.value(link, EX.source)
        target = graph.value(link, EX.target)
        latency = int(graph.value(link, EX.latency))
        adjacency.setdefault(source, []).append((target, latency))
        adjacency.setdefault(target, []).append((source, latency))

    results = []
    for database, size in databases:
        distances = {database: 0}
        paths = {database: [database]}
        queue = [(0, str(database), database)]
        while queue:
            distance, _, node = heapq.heappop(queue)
            if distance != distances[node]:
                continue
            for neighbor, weight in adjacency.get(node, []):
                candidate = distance + weight
                if candidate < distances.get(neighbor, float("inf")):
                    distances[neighbor] = candidate
                    paths[neighbor] = paths[node] + [neighbor]
                    heapq.heappush(queue, (candidate, str(neighbor), neighbor))

        eligible = [node for node, capacity in capacities.items()
                    if capacity >= size and node in distances]
        assert eligible, "Verifier fixture unexpectedly has no eligible storage node."
        target = min(eligible, key=lambda node: (distances[node], str(node)))
        results.append({
            "database_id": str(database),
            "target_storage_id": str(target),
            "path": [str(node) for node in paths[target]],
            "total_latency": distances[target],
        })
    return sorted(results, key=lambda item: item["database_id"])


def test_router_recomputes_from_changed_rdf_and_traverses_reverse_links():
    suffix = uuid.uuid4().hex
    base = f"http://verification.invalid/{suffix}#"
    ttl = f'''@prefix ex: <{base}> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
ex:AlphaDB a ex:Database ; ex:dbSize 90 ; ex:needsBackup "true"^^xsd:boolean .
ex:ZuluDB a ex:Database ; ex:dbSize 180 ; ex:needsBackup "true"^^xsd:boolean .
ex:IgnoredDB a ex:Database ; ex:dbSize 1 ; ex:needsBackup "false"^^xsd:boolean .
ex:ExactStore a ex:StorageNode ; ex:availableCapacity 90 .
ex:BigStore a ex:StorageNode ; ex:availableCapacity 500 .
ex:FarStore a ex:StorageNode ; ex:availableCapacity 300 .
ex:X a ex:NetworkDevice . ex:Y a ex:NetworkDevice . ex:Z a ex:NetworkDevice .
ex:L1 a ex:NetworkLink ; ex:source ex:X ; ex:target ex:AlphaDB ; ex:latency 4 .
ex:L2 a ex:NetworkLink ; ex:source ex:ExactStore ; ex:target ex:X ; ex:latency 6 .
ex:L3 a ex:NetworkLink ; ex:source ex:Y ; ex:target ex:X ; ex:latency 3 .
ex:L4 a ex:NetworkLink ; ex:source ex:BigStore ; ex:target ex:Y ; ex:latency 5 .
ex:L5 a ex:NetworkLink ; ex:source ex:Y ; ex:target ex:ZuluDB ; ex:latency 2 .
ex:L6 a ex:NetworkLink ; ex:source ex:FarStore ; ex:target ex:Z ; ex:latency 1 .
ex:L7 a ex:NetworkLink ; ex:source ex:Z ; ex:target ex:Y ; ex:latency 20 .
'''
    schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "type": "array",
        "items": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "database_id": {"type": "string"},
                "target_storage_id": {"type": "string"},
                "path": {"type": "array", "items": {"type": "string"}},
                "total_latency": {"type": "integer"}
            },
            "required": ["database_id", "target_storage_id", "path", "total_latency"]
        }
    }
    expected = derive_expected(ttl)
    result, produced = execute_with_files(ttl, schema)
    assert result.returncode == 0, \
        f"Script failed on a valid changed RDF graph:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert produced is not None, "Script did not create the routing plan for the changed RDF graph."
    try:
        actual = json.loads(produced.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f"Changed-input output is not valid UTF-8 JSON: {exc}")
    validate(actual, schema)
    assert actual == expected, \
        "Routing plan was not recomputed correctly from the changed RDF graph."


def test_schema_is_loaded_and_validation_occurs_before_output_is_written():
    with open(TTL_PATH, "r", encoding="utf-8") as f:
        ttl = f.read()
    rejecting_schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "type": "array",
        "maxItems": 0
    }
    result, produced = execute_with_files(ttl, rejecting_schema)
    assert produced is None, \
        "backup_router.py wrote a routing plan that is invalid under output_schema.json; validation must happen before writing."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
