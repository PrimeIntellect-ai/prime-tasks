#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

C_FILE = "/home/user/audit.c"
RUNNER = "/home/user/audit_runner"
DATABASE = "/home/user/finance_data.db"
REPORT = "/home/user/audit_report.json"
COMPILED = "/tmp/audit_compiled_from_source"


def run_artifact(path):
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run([path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=15)
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT), f"{path} did not create {REPORT}."
    try:
        with open(REPORT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{path} produced invalid JSON: {exc}")
    assert "total_3_cycles" in data, "Key 'total_3_cycles' missing in audit report."
    assert "total_cycle_exposure" in data, "Key 'total_cycle_exposure' missing in audit report."
    return data


def test_audit_c_exists():
    """Check if the C source file exists."""
    assert os.path.isfile(C_FILE), f"C source file {C_FILE} is missing."


def test_audit_runner_exists_and_executable():
    """Check if the compiled executable exists and is executable."""
    assert os.path.isfile(RUNNER), f"Executable {RUNNER} is missing."
    assert os.access(RUNNER, os.X_OK), f"File {RUNNER} is not executable."
    with open(RUNNER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{RUNNER} is not a compiled executable."


def test_audit_report_contents():
    """Execute the submitted runner and check its report for the original database."""
    data = run_artifact(RUNNER)

    expected_cycles = 2
    expected_exposure = 630

    actual_cycles = data["total_3_cycles"]
    actual_exposure = data["total_cycle_exposure"]

    assert actual_cycles == expected_cycles, f"Expected total_3_cycles to be {expected_cycles}, got {actual_cycles}."
    assert actual_exposure == expected_exposure, f"Expected total_cycle_exposure to be {expected_exposure}, got {actual_exposure}."


def derive_expected(transactions):
    edge_amount = {(src, dst): amount for src, dst, amount in transactions}
    nodes = set(itertools.chain.from_iterable((src, dst) for src, dst, _ in transactions))
    cycles = set()
    participating = set()

    for a, b, c in itertools.permutations(nodes, 3):
        edges = ((a, b), (b, c), (c, a))
        if all(edge in edge_amount for edge in edges):
            rotations = ((a, b, c), (b, c, a), (c, a, b))
            cycles.add(min(rotations))
            participating.update(edges)

    exposure = sum(edge_amount[edge] for edge in participating)
    return len(cycles), exposure


def test_source_and_runner_on_unseen_database():
    """Compile the submitted C source and exercise both artifacts on fresh data."""
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_FILE, "-o", COMPILED, "-lsqlite3", "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"audit.c did not compile: {compile_result.stderr}"
    assert os.path.isfile(COMPILED) and os.access(COMPILED, os.X_OK)

    token = secrets.token_hex(5)
    names = [f"ACCT_{token}_{i}_{secrets.token_hex(2)}" for i in range(15)]
    a, b, c, d, e, f, g, h, i, j, k, l, m, n, o = names

    def amount():
        return secrets.randbelow(9000) + 1

    transactions = [
        (a, b, amount()),
        (b, c, amount()), (c, a, amount()),
        (b, d, amount()), (d, a, amount()),
        (e, f, amount()), (f, g, amount()), (g, e, amount()),
        (h, i, amount()), (i, h, amount()),
        (j, k, amount()), (k, l, amount()), (l, m, amount()), (m, j, amount()),
        (n, o, amount()),
    ]
    secrets.SystemRandom().shuffle(transactions)
    expected_cycles, expected_exposure = derive_expected(transactions)

    backup_dir = tempfile.mkdtemp(prefix="audit_verify_")
    moved = []
    report_backup = None
    try:
        if os.path.exists(REPORT):
            report_backup = os.path.join(backup_dir, "audit_report.json")
            shutil.copy2(REPORT, report_backup)

        for suffix in ("", "-wal", "-shm", "-journal"):
            original = DATABASE + suffix
            if os.path.exists(original):
                backup = os.path.join(backup_dir, "database" + (suffix or "-main"))
                os.replace(original, backup)
                moved.append((backup, original))

        connection = sqlite3.connect(DATABASE)
        try:
            connection.execute("CREATE TABLE nosql_store (doc_id TEXT PRIMARY KEY, document JSON)")
            for index, (src, dst, amt) in enumerate(transactions):
                document = json.dumps({
                    "type": "transaction",
                    "details": {"src": src, "dst": dst, "amt": amt}
                })
                connection.execute(
                    "INSERT INTO nosql_store (doc_id, document) VALUES (?, ?)",
                    (f"hidden_{token}_{index}", document)
                )
            connection.execute(
                "INSERT INTO nosql_store (doc_id, document) VALUES (?, ?)",
                (f"profile_{token}", json.dumps({"type": "account", "details": {"src": c, "dst": e, "amt": 999999}}))
            )
            connection.commit()
        finally:
            connection.close()

        for artifact in (RUNNER, COMPILED):
            data = run_artifact(artifact)
            actual_cycles = data["total_3_cycles"]
            actual_exposure = data["total_cycle_exposure"]
            assert isinstance(actual_cycles, int) and not isinstance(actual_cycles, bool)
            assert isinstance(actual_exposure, int) and not isinstance(actual_exposure, bool)
            assert actual_cycles == expected_cycles, (
                f"{artifact} reported {actual_cycles} cycles; expected {expected_cycles}."
            )
            assert actual_exposure == expected_exposure, (
                f"{artifact} reported exposure {actual_exposure}; expected {expected_exposure}."
            )
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            path = DATABASE + suffix
            if os.path.exists(path):
                os.remove(path)
        for backup, original in moved:
            os.replace(backup, original)
        if report_backup is not None:
            shutil.copy2(report_backup, REPORT)
        elif os.path.exists(REPORT):
            os.remove(REPORT)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
