#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import json
import secrets
import subprocess
import itertools
import pytest

LOG_MARKER = "validator_verifier_" + secrets.token_hex(16)


def run_psql(sql, database="backup_db"):
    return subprocess.run(
        ["sudo", "-u", "postgres", "psql", "-v", "ON_ERROR_STOP=1", "-d", database, "-c", sql],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    )


@pytest.fixture(scope="session", autouse=True)
def enable_statement_logging():
    run_psql("ALTER SYSTEM SET log_statement = 'all'; SELECT pg_reload_conf();", "postgres")
    run_psql("SELECT '%s';" % LOG_MARKER, "backup_db")


def run_validator(filepath):
    # Run the go tool from the correct directory
    cmd = ["go", "run", "validator.go", filepath]
    try:
        result = subprocess.run(
            cmd,
            cwd="/app/backup-service",
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return -1, "TIMEOUT"
    except Exception as e:
        return -1, str(e)


def test_validator_artifact_exists():
    path = "/app/backup-service/validator.go"
    assert os.path.isfile(path), "validator.go is missing or is not a regular file"


def test_clean_corpus():
    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"

    failed_files = []
    for filepath in clean_files:
        code, stdout = run_validator(filepath)
        if code != 0 or "ACCEPT" not in stdout:
            failed_files.append(os.path.basename(filepath))

    assert len(failed_files) == 0, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}"


def test_evil_corpus():
    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    bypassed_files = []
    for filepath in evil_files:
        code, stdout = run_validator(filepath)
        if code != 1 or "REJECT" not in stdout:
            bypassed_files.append(os.path.basename(filepath))

    assert len(bypassed_files) == 0, f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}"


def induced_connected(subset, edges):
    selected = set(subset)
    if not selected:
        return False
    seen = {next(iter(selected))}
    while True:
        expanded = set(seen)
        for a, b in edges:
            if a in selected and b in selected:
                if a in seen:
                    expanded.add(b)
                if b in seen:
                    expanded.add(a)
        if expanded == seen:
            return seen == selected
        seen = expanded


def test_unseen_random_schema_subsets():
    rng = secrets.SystemRandom()
    n = 9

    while True:
        edges = {(i, i + 1) for i in range(n - 1)}
        for i in range(n):
            for j in range(i + 2, n):
                if rng.random() < 0.18:
                    edges.add((i, j))

        connected = []
        disconnected = []
        for size in range(2, 7):
            for subset in itertools.combinations(range(n), size):
                if induced_connected(subset, edges):
                    connected.append(subset)
                else:
                    disconnected.append(subset)
        if len(connected) >= 6 and len(disconnected) >= 6:
            break

    token = secrets.token_hex(8)
    names = [f"v_{token}_{i}_{secrets.token_hex(3)}" for i in range(n)]

    statements = []
    for i, name in enumerate(names):
        columns = ["id INTEGER PRIMARY KEY"]
        for a, b in sorted(edges):
            if b == i:
                columns.append(f"fk_{a} INTEGER REFERENCES {names[a]}(id)")
        statements.append(f"CREATE TABLE {name} ({', '.join(columns)});")
    run_psql("\n".join(statements))

    rng.shuffle(connected)
    rng.shuffle(disconnected)
    cases = [(s, True) for s in connected[:6]] + [(s, False) for s in disconnected[:6]]
    rng.shuffle(cases)

    case_dir = f"/tmp/validator_cases_{secrets.token_hex(10)}"
    os.makedirs(case_dir, mode=0o700)
    failures = []
    for subset, should_accept in cases:
        filename = os.path.join(case_dir, secrets.token_hex(12) + ".json")
        requested = [names[i] for i in subset]
        rng.shuffle(requested)
        with open(filename, "w") as f:
            json.dump({"tables": requested}, f)

        code, stdout = run_validator(filename)
        if should_accept:
            if code != 0 or "ACCEPT" not in stdout:
                failures.append((requested, "ACCEPT", code, stdout))
        else:
            if code != 1 or "REJECT" not in stdout:
                failures.append((requested, "REJECT", code, stdout))

    assert not failures, f"Validator failed randomized PostgreSQL graph cases: {failures}"


def test_postgresql_schema_metadata_was_queried():
    log_files = glob.glob("/var/log/postgresql/*.log")
    assert log_files, "No PostgreSQL statement log was found"

    suffixes = []
    for path in log_files:
        with open(path, "r", errors="replace") as f:
            contents = f.read()
        marker_pos = contents.rfind(LOG_MARKER)
        if marker_pos >= 0:
            suffixes.append(contents[marker_pos + len(LOG_MARKER):].lower())

    assert suffixes, "Could not locate the verifier marker in PostgreSQL logs"
    logged_after_marker = "\n".join(suffixes)
    assert ("pg_constraint" in logged_after_marker or
            "information_schema" in logged_after_marker), (
        "Validator did not query pg_constraint or information_schema while validating requests"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
