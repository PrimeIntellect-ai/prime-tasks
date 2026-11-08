#!/bin/bash
set -o pipefail
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:${PATH}"

cat << 'INITIAL_TEST_EOF' > /tmp/test_initial_state.py
import os
import json


def test_vulnerable_dbs_json():
    json_path = "/home/user/vulnerable_dbs.json"
    assert os.path.isfile(json_path), f"Expected JSON output file {json_path} does not exist."

    with open(json_path, "r") as f:
        data = json.load(f)

    assert isinstance(data, list), f"Expected JSON array in {json_path}, but got {type(data).__name__}."
    assert data == ["db3", "db4"], f"Expected ['db3', 'db4'] in {json_path}, but got {data}."


def test_query_plan_txt():
    txt_path = "/home/user/query_plan.txt"
    assert os.path.isfile(txt_path), f"Expected query plan file {txt_path} does not exist."
    with open(txt_path, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"File {txt_path} is empty. It should contain the EXPLAIN output."


def test_kuzu_db_dir():
    db_dir = "/home/user/kuzu_db"
    assert os.path.isdir(db_dir), f"Expected KuzuDB directory {db_dir} does not exist."


def test_rust_project_exists():
    cargo_toml = "/home/user/backup_auditor/Cargo.toml"
    assert os.path.isfile(cargo_toml), f"Expected Rust project file {cargo_toml} does not exist."
INITIAL_TEST_EOF

cat << 'FIXTURE_EOF' > /tmp/make_dynamic_fixture.py
import csv
import os
import secrets

base = secrets.token_hex(8)
ids = {name: f"{base}_{name}" for name in ("safe30", "short", "inactive", "noncritical", "none", "multi")}
policies = {name: f"{base}_p_{name}" for name in ("valid", "short", "inactive", "valid2")}

graph_dir = "/home/user/graph_data"
os.makedirs(graph_dir, exist_ok=True)

with open(os.path.join(graph_dir, "databases.csv"), "w", newline="") as f:
    csv.writer(f).writerows([
        [ids["safe30"], "SafeThirty", "true"],
        [ids["short"], "TooShort", "true"],
        [ids["inactive"], "InactivePolicy", "true"],
        [ids["noncritical"], "NotCritical", "false"],
        [ids["none"], "NoPolicy", "true"],
        [ids["multi"], "MultiplePolicies", "true"],
    ])

with open(os.path.join(graph_dir, "policies.csv"), "w", newline="") as f:
    csv.writer(f).writerows([
        [policies["valid"], "30", "true"],
        [policies["short"], "29", "true"],
        [policies["inactive"], "90", "false"],
        [policies["valid2"], "60", "true"],
    ])

with open(os.path.join(graph_dir, "has_policy.csv"), "w", newline="") as f:
    csv.writer(f).writerows([
        [ids["safe30"], policies["valid"]],
        [ids["short"], policies["short"]],
        [ids["inactive"], policies["inactive"]],
        [ids["noncritical"], policies["valid"]],
        [ids["multi"], policies["short"]],
        [ids["multi"], policies["valid2"]],
    ])
FIXTURE_EOF

cat << 'FINAL_TEST_EOF' > /tmp/test_dynamic_state.py
import csv
import json
import os
import re

GRAPH = "/home/user/graph_data"


def as_bool(value):
    return value.strip().lower() == "true"


def derive_expected():
    with open(os.path.join(GRAPH, "databases.csv"), newline="") as f:
        databases = {row[0]: as_bool(row[2]) for row in csv.reader(f)}
    with open(os.path.join(GRAPH, "policies.csv"), newline="") as f:
        policies = {row[0]: (int(row[1]), as_bool(row[2])) for row in csv.reader(f)}
    with open(os.path.join(GRAPH, "has_policy.csv"), newline="") as f:
        relationships = list(csv.reader(f))

    adequate = set()
    for db_id, policy_id in relationships:
        retention, active = policies[policy_id]
        if active and retention >= 30:
            adequate.add(db_id)
    return sorted(db_id for db_id, critical in databases.items() if critical and db_id not in adequate)


def test_dynamic_vulnerable_dbs_json():
    path = "/home/user/vulnerable_dbs.json"
    assert os.path.isfile(path), "The executed Rust program did not create vulnerable_dbs.json"
    with open(path) as f:
        data = json.load(f)
    assert isinstance(data, list), "Output must be a JSON array"
    assert all(type(item) is str for item in data), "Every array element must be a string literal"
    assert data == sorted(data), "Database IDs must be alphabetically sorted"
    assert data == derive_expected(), f"Expected {derive_expected()}, got {data}"


def test_query_plan_txt():
    path = "/home/user/query_plan.txt"
    assert os.path.isfile(path), "The executed Rust program did not create query_plan.txt"
    with open(path) as f:
        content = f.read().strip()
    assert content, "query_plan.txt is empty"
    upper = content.upper()
    assert any(marker in upper for marker in ("PROJECTION", "FILTER", "SCAN", "JOIN", "EXTEND")), \
        "query_plan.txt does not resemble a Kuzu EXPLAIN plan"


def test_kuzu_db_dir():
    path = "/home/user/kuzu_db"
    assert os.path.isdir(path), f"Expected KuzuDB directory {path} does not exist."
    assert any(os.path.getsize(os.path.join(root, name)) > 0
               for root, _, names in os.walk(path) for name in names), \
        "KuzuDB directory contains no nonempty database files"


def test_rust_project_exists_and_declares_dependencies():
    cargo_path = "/home/user/backup_auditor/Cargo.toml"
    assert os.path.isfile(cargo_path), f"Expected Rust project file {cargo_path} does not exist."
    cargo = open(cargo_path).read()
    assert re.search(r"(?m)^\s*kuzu\s*=", cargo), "Cargo.toml must declare the kuzu crate"
    assert re.search(r"(?m)^\s*serde_json\s*=", cargo), "Cargo.toml must declare serde_json"


def test_source_contains_required_kuzu_operations_and_validation():
    source_root = "/home/user/backup_auditor/src"
    files = []
    for root, _, names in os.walk(source_root):
        for name in names:
            if name.endswith(".rs"):
                files.append(os.path.join(root, name))
    assert files, "Rust project has no source files"
    source = "\n".join(open(path).read() for path in files)
    normalized = re.sub(r"\s+", " ", source.upper())
    for required in ("CREATE NODE TABLE", "CREATE REL TABLE", "COPY", "EXPLAIN", "HAS_POLICY", "BACKUPPOLICY"):
        assert required in normalized, f"Rust source is missing required Kuzu operation: {required}"
    assert "SERDE_JSON" in normalized, "Rust source does not use serde_json to validate/serialize the output"
FINAL_TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_initial_state.py -x --tb=short 2>&1 \
   && python3 /tmp/make_dynamic_fixture.py \
   && rm -rf /home/user/kuzu_db /home/user/query_plan.txt /home/user/vulnerable_dbs.json \
   && timeout 300s cargo run --quiet --manifest-path /home/user/backup_auditor/Cargo.toml 2>&1 \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
