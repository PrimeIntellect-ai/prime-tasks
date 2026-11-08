#!/bin/bash
mkdir -p /logs/verifier

DB_BACKUP="/tmp/backup_graph.db.verifier_backup"
if cp /home/user/backup_graph.db "$DB_BACKUP"; then
    trap 'cp "$DB_BACKUP" /home/user/backup_graph.db 2>/dev/null || true' EXIT
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import sqlite3
import subprocess
import uuid

import pytest

HOME = pathlib.Path("/home/user")
SOURCE = HOME / "extract_chain.go"
OUTPUT = HOME / "dependency_chains.json"
DB = HOME / "backup_graph.db"
BINARY = pathlib.Path("/tmp/extract_chain_verifier")


def run_program(*args, expect_success=True):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(BINARY), *args],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if expect_success:
        assert result.returncode == 0, (
            f"Program failed for arguments {args}:\nstdout={result.stdout}\nstderr={result.stderr}"
        )
        assert OUTPUT.exists(), "Program did not create /home/user/dependency_chains.json."
    return result


def load_strict_output():
    try:
        with OUTPUT.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{OUTPUT} is not valid JSON: {exc}")

    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    required_keys = {"service_name", "database_name", "storage_name"}
    for item in data:
        assert isinstance(item, dict), "Every JSON array element must be an object."
        assert set(item) == required_keys, f"Unexpected output object schema: {item}"
        assert all(isinstance(item[k], str) for k in required_keys), f"Names must be strings: {item}"
    return data


def canonical(data):
    return sorted(
        (x["service_name"], x["database_name"], x["storage_name"])
        for x in data
    )


def test_module_source_and_build():
    assert SOURCE.exists(), f"Go source file {SOURCE} does not exist."
    go_mod = HOME / "go.mod"
    assert go_mod.exists(), "/home/user/go.mod does not exist."
    module_lines = [line.strip() for line in go_mod.read_text(encoding="utf-8").splitlines()]
    assert "module backup-audit" in module_lines, "The Go module must be named backup-audit."

    content = SOURCE.read_text(encoding="utf-8")
    assert "?" in content, "The Go code does not appear to use parameterized queries (missing '?')."

    build = subprocess.run(
        ["go", "build", "-o", str(BINARY), str(SOURCE)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"Go program does not build:\n{build.stdout}\n{build.stderr}"
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), "Build did not produce an executable."


def test_requires_exactly_one_argument():
    no_args = run_program(expect_success=False)
    assert no_args.returncode != 0, "Program must reject invocation with no service name."

    two_args = run_program("PaymentService", "extra", expect_success=False)
    assert two_args.returncode != 0, "Program must reject invocation with more than one argument."


def test_dependency_chains_json():
    run_program("PaymentService")
    data = load_strict_output()

    expected_chains = [
        {"service_name": "PaymentService", "database_name": "TxDB", "storage_name": "FastBlock"},
        {"service_name": "PaymentService", "database_name": "LedgerDB", "storage_name": "ColdArchive"},
    ]
    assert len(data) == 2, (
        f"Expected exactly 2 elements in the JSON array, got {len(data)}. "
        "Ensure cross-joins are removed."
    )
    for expected in expected_chains:
        assert expected in data, f"Missing expected chain in JSON: {expected}"
    assert canonical(data) == canonical(expected_chains), "Output contains incorrect or duplicate chains."


def test_dynamic_traversal_and_parameterization():
    token = uuid.uuid4().hex
    service_name = f"AuditSvc_{token}_O'Reilly"
    other_service = f"OtherSvc_{token}"
    db_names = [f"AuditDB_A_{token}", f"AuditDB_B_{token}"]
    storage_names = [f"AuditStorage_A_{token}", f"AuditStorage_B_{token}"]
    decoy_db = f"DecoyDB_{token}"
    decoy_storage = f"DecoyStorage_{token}"

    conn = sqlite3.connect(DB)
    try:
        next_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM Nodes").fetchone()[0]
        ids = {
            "service": next_id,
            "other_service": next_id + 1,
            "db1": next_id + 2,
            "db2": next_id + 3,
            "storage1": next_id + 4,
            "storage2": next_id + 5,
            "decoy_db": next_id + 6,
            "decoy_storage": next_id + 7,
        }
        nodes = [
            (ids["service"], "Service", json.dumps({"name": service_name})),
            (ids["other_service"], "Service", json.dumps({"name": other_service})),
            (ids["db1"], "Database", json.dumps({"name": db_names[0]})),
            (ids["db2"], "Database", json.dumps({"name": db_names[1]})),
            (ids["storage1"], "Storage", json.dumps({"name": storage_names[0]})),
            (ids["storage2"], "Storage", json.dumps({"name": storage_names[1]})),
            (ids["decoy_db"], "Database", json.dumps({"name": decoy_db})),
            (ids["decoy_storage"], "Storage", json.dumps({"name": decoy_storage})),
        ]
        conn.executemany("INSERT INTO Nodes(id, label, props) VALUES (?, ?, ?)", nodes)
        conn.executemany(
            "INSERT INTO Edges(source, target, rel_type) VALUES (?, ?, ?)",
            [
                (ids["service"], ids["db1"], "USES_DB"),
                (ids["service"], ids["db2"], "USES_DB"),
                (ids["db1"], ids["storage1"], "STORED_ON"),
                (ids["db2"], ids["storage2"], "STORED_ON"),
                # Decoys expose missing endpoint and relationship-type constraints.
                (ids["service"], ids["decoy_db"], "NOT_USES_DB"),
                (ids["decoy_db"], ids["decoy_storage"], "STORED_ON"),
                (ids["other_service"], ids["decoy_db"], "USES_DB"),
                (ids["db1"], ids["decoy_storage"], "NOT_STORED_ON"),
            ],
        )
        conn.commit()

        oracle_rows = conn.execute(
            """
            SELECT json_extract(s.props, '$.name'),
                   json_extract(d.props, '$.name'),
                   json_extract(st.props, '$.name')
            FROM Nodes AS s
            JOIN Edges AS e1 ON e1.source = s.id AND e1.rel_type = 'USES_DB'
            JOIN Nodes AS d ON d.id = e1.target AND d.label = 'Database'
            JOIN Edges AS e2 ON e2.source = d.id AND e2.rel_type = 'STORED_ON'
            JOIN Nodes AS st ON st.id = e2.target AND st.label = 'Storage'
            WHERE s.label = 'Service' AND json_extract(s.props, '$.name') = ?
            """,
            (service_name,),
        ).fetchall()
    finally:
        conn.close()

    expected = [
        {"service_name": s, "database_name": d, "storage_name": st}
        for s, d, st in oracle_rows
    ]
    assert len(expected) == 2, "Verifier fixture did not produce two reference chains."

    run_program(service_name)
    actual = load_strict_output()
    assert canonical(actual) == canonical(expected), (
        "Program did not traverse the dynamically added Service -> Database -> Storage edges correctly."
    )

    # This has no matching service. Interpolating it into SQL would alter the query;
    # binding it as a parameter must safely return an empty JSON array.
    injection = f"missing_{token}' OR 1=1 --"
    run_program(injection)
    assert load_strict_output() == [], "Service input is not safely parameterized or empty results are not an array."

    # Leave the required final artifact in its instructed PaymentService state.
    run_program("PaymentService")
    final_data = load_strict_output()
    expected_payment = [
        {"service_name": "PaymentService", "database_name": "TxDB", "storage_name": "FastBlock"},
        {"service_name": "PaymentService", "database_name": "LedgerDB", "storage_name": "ColdArchive"},
    ]
    assert canonical(final_data) == canonical(expected_payment)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
