#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import random
import re
import stat
import subprocess
import uuid

HOME = "/home/user"
PROGRAM = os.path.join(HOME, "analyze_backup.go")
NODES = os.path.join(HOME, "nodes.json")
EDGES = os.path.join(HOME, "edges.json")
SCHEMA_OUT = os.path.join(HOME, "schema_errors.json")
DBS_OUT = os.path.join(HOME, "failed_s3_dbs.json")
INDEX_OUT = os.path.join(HOME, "index_strategy.txt")
OUTPUTS = [SCHEMA_OUT, DBS_OUT, INDEX_OUT]


def assert_program_exists():
    assert os.path.exists(PROGRAM), f"{PROGRAM} is missing."
    mode = os.lstat(PROGRAM).st_mode
    assert stat.S_ISREG(mode), f"{PROGRAM} must be a regular Go source file."


def run_program():
    assert_program_exists()
    for path in OUTPUTS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["go", "run", PROGRAM],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, (
        f"Running {PROGRAM} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_json_array(path):
    assert os.path.isfile(path), f"{path} is missing."
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{path} is not a valid JSON file: {exc}")
    assert isinstance(data, list), f"{path} should contain a JSON array."
    assert all(isinstance(item, str) for item in data), (
        f"{path} must contain only strings."
    )
    return data


def check_index_strategy():
    file_path = INDEX_OUT
    assert os.path.isfile(file_path), f"{file_path} is missing."
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert "\n" not in content and "\r" not in content, (
        f"The Cypher query in {file_path} must be a single line."
    )

    # Preserve the original accepted forms, but require the entire content to match.
    normalized_content = re.sub(r"\s+", " ", content).strip(";").lower()
    expected_patterns = [
        r"create index for \(b:backupjob\) on \(b\.status\)",
        r"create index on :backupjob\(status\)",
    ]
    matched = any(re.fullmatch(pattern, normalized_content) for pattern in expected_patterns)
    assert matched, (
        f"The Cypher query in {file_path} is not a valid index creation "
        f"statement for BackupJob.status. Got: {content}"
    )


def valid_iso8601(value):
    if not isinstance(value, str):
        return False
    try:
        datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def derive_expected(nodes, edges):
    by_id = {node.get("id"): node for node in nodes}
    schema_errors = set()

    for node in nodes:
        if node.get("label") != "BackupJob":
            continue
        props = node.get("properties")
        if not isinstance(props, dict):
            schema_errors.add(node.get("id"))
            continue
        if not isinstance(props.get("status"), str) or not valid_iso8601(props.get("timestamp")):
            schema_errors.add(node.get("id"))

    has_backup = set()
    stored_on = set()
    for edge in edges:
        pair = (edge.get("source"), edge.get("target"))
        if edge.get("type") == "HAS_BACKUP":
            has_backup.add(pair)
        elif edge.get("type") == "STORED_ON":
            stored_on.add(pair)

    failed_s3_dbs = set()
    for db in nodes:
        if db.get("label") != "Database":
            continue
        for job in nodes:
            if job.get("label") != "BackupJob" or (db.get("id"), job.get("id")) not in has_backup:
                continue
            job_props = job.get("properties", {})
            if not isinstance(job_props, dict) or job_props.get("status") != "FAILED":
                continue
            for storage in nodes:
                storage_props = storage.get("properties", {})
                if (
                    storage.get("label") == "StorageNode"
                    and isinstance(storage_props, dict)
                    and storage_props.get("type") == "S3"
                    and (job.get("id"), storage.get("id")) in stored_on
                ):
                    name = db.get("properties", {}).get("name")
                    if isinstance(name, str):
                        failed_s3_dbs.add(name)

    return schema_errors, failed_s3_dbs


def write_fixture(nodes, edges):
    with open(NODES, "w", encoding="utf-8") as f:
        json.dump(nodes, f)
    with open(EDGES, "w", encoding="utf-8") as f:
        json.dump(edges, f)


def check_outputs(expected_schema, expected_dbs):
    schema_data = load_json_array(SCHEMA_OUT)
    actual_errors = set(schema_data)
    assert actual_errors == expected_schema, (
        f"Expected schema errors to be {expected_schema}, but got {actual_errors}."
    )

    db_data = load_json_array(DBS_OUT)
    actual_dbs = set(db_data)
    assert actual_dbs == expected_dbs, (
        f"Expected failed S3 DBs to be {expected_dbs}, but got {actual_dbs}."
    )
    check_index_strategy()


def make_dynamic_fixture():
    token = uuid.uuid4().hex
    ids = {name: f"{name}-{token}" for name in [
        "dbA", "dbB", "dbC", "jobGood", "jobMissing", "jobInvalid",
        "jobSuccess", "jobNfs", "s3", "nfs"
    ]}
    nodes = [
        {"id": ids["dbA"], "label": "Database", "properties": {"name": f"primary-{token}"}},
        {"id": ids["dbB"], "label": "Database", "properties": {"name": f"secondary-{token}"}},
        {"id": ids["dbC"], "label": "Database", "properties": {"name": f"analytics-{token}"}},
        {"id": ids["jobGood"], "label": "BackupJob", "properties": {"status": "FAILED", "timestamp": "2025-04-03T12:34:56Z"}},
        {"id": ids["jobMissing"], "label": "BackupJob", "properties": {"status": "SUCCESS"}},
        {"id": ids["jobInvalid"], "label": "BackupJob", "properties": {"status": "FAILED", "timestamp": "not-a-time"}},
        {"id": ids["jobSuccess"], "label": "BackupJob", "properties": {"status": "SUCCESS", "timestamp": "2025-04-04T01:02:03+02:00"}},
        {"id": ids["jobNfs"], "label": "BackupJob", "properties": {"status": "FAILED", "timestamp": "2025-04-05T06:07:08Z"}},
        {"id": ids["s3"], "label": "StorageNode", "properties": {"type": "S3"}},
        {"id": ids["nfs"], "label": "StorageNode", "properties": {"type": "NFS"}},
    ]
    edges = [
        {"source": ids["dbA"], "target": ids["jobGood"], "type": "HAS_BACKUP"},
        {"source": ids["jobGood"], "target": ids["s3"], "type": "STORED_ON"},
        {"source": ids["dbB"], "target": ids["jobSuccess"], "type": "HAS_BACKUP"},
        {"source": ids["jobSuccess"], "target": ids["s3"], "type": "STORED_ON"},
        {"source": ids["dbC"], "target": ids["jobNfs"], "type": "HAS_BACKUP"},
        {"source": ids["jobNfs"], "target": ids["nfs"], "type": "STORED_ON"},
        {"source": ids["dbB"], "target": ids["jobInvalid"], "type": "HAS_BACKUP"},
        {"source": ids["jobInvalid"], "target": ids["s3"], "type": "STORED_ON"},
    ]
    random.SystemRandom().shuffle(nodes)
    random.SystemRandom().shuffle(edges)
    return nodes, edges


def main():
    assert_program_exists()
    with open(NODES, "rb") as f:
        original_nodes = f.read()
    with open(EDGES, "rb") as f:
        original_edges = f.read()

    try:
        # Execute against the original fixture and preserve its original assertions.
        run_program()
        check_outputs({"job2", "job3"}, {"prod-db-1"})

        # Replace the inputs with an unpredictable fixture and independently derive answers.
        nodes, edges = make_dynamic_fixture()
        expected_schema, expected_dbs = derive_expected(nodes, edges)
        write_fixture(nodes, edges)
        run_program()
        check_outputs(expected_schema, expected_dbs)
        assert_program_exists()
    finally:
        with open(NODES, "wb") as f:
            f.write(original_nodes)
        with open(EDGES, "wb") as f:
            f.write(original_edges)


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
