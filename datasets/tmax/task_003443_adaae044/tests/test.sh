#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid
import pytest

VALIDATOR_PATH = "/home/user/validator"
VALIDATOR_SOURCE = "/home/user/validator.c"
SQLITE_DIR = "/app/sqlite"
SQLITE_LIB = os.path.join(SQLITE_DIR, "libsqlite3.a")
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
REBUILT_VALIDATOR = "/tmp/rebuilt_validator"


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, timeout=60, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command!r}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def assert_classification(executable, query_path, expected):
    try:
        result = subprocess.run(
            [executable, query_path], capture_output=True, text=True, timeout=5
        )
    except Exception as exc:
        pytest.fail(f"Could not run {executable} on {query_path}: {exc}")

    assert result.returncode == 0, (
        f"{executable} returned {result.returncode} for {query_path}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected, (
        f"{executable} produced {result.stdout!r} for {query_path}; expected {expected}"
    )


def test_required_build_artifacts_and_source():
    assert os.path.isfile(VALIDATOR_SOURCE), f"Source not found at {VALIDATOR_SOURCE}"
    assert os.path.isfile(VALIDATOR_PATH), f"Validator executable not found at {VALIDATOR_PATH}"
    assert os.access(VALIDATOR_PATH, os.X_OK), f"Validator at {VALIDATOR_PATH} is not executable"
    with open(VALIDATOR_PATH, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "Validator is not a compiled ELF executable"

    assert os.path.isfile(os.path.join(SQLITE_DIR, "Makefile")), "SQLite Makefile is missing"
    run_checked(["make", "-B", "-C", SQLITE_DIR, "libsqlite3.a"])
    assert os.path.isfile(SQLITE_LIB), "Makefile did not produce libsqlite3.a"

    members = run_checked(["ar", "t", SQLITE_LIB]).stdout.splitlines()
    assert "sqlite3.o" in members, "libsqlite3.a does not contain sqlite3.o"
    assert not any(member.endswith(".c") for member in members), (
        "libsqlite3.a incorrectly contains C source instead of compiled objects"
    )

    auth_source = "/tmp/check_sqlite_authorizer.c"
    auth_binary = "/tmp/check_sqlite_authorizer"
    with open(auth_source, "w") as output:
        output.write(r'''#include "sqlite3.h"
static int auth(void *p, int a, const char *b, const char *c, const char *d, const char *e) {
    (void)p; (void)a; (void)b; (void)c; (void)d; (void)e;
    return SQLITE_OK;
}
int main(void) {
    sqlite3 *db = 0;
    if (sqlite3_open(":memory:", &db) != SQLITE_OK) return 2;
    if (sqlite3_set_authorizer(db, auth, 0) != SQLITE_OK) return 3;
    sqlite3_close(db);
    return 0;
}
''')
    run_checked([
        "gcc", "-I", SQLITE_DIR, auth_source, SQLITE_LIB,
        "-ldl", "-lpthread", "-lm", "-o", auth_binary
    ])
    run_checked([auth_binary])

    run_checked([
        "gcc", "-I", SQLITE_DIR, VALIDATOR_SOURCE, SQLITE_LIB,
        "-ldl", "-lpthread", "-lm", "-o", REBUILT_VALIDATOR
    ])
    symbols = run_checked(["nm", "-g", REBUILT_VALIDATOR]).stdout
    assert re.search(r"\b[Tt]\s+sqlite3_open(?:_v2)?$", symbols, re.MULTILINE), (
        "Rebuilt validator does not contain a statically linked sqlite3_open implementation"
    )
    assert re.search(r"\b[Tt]\s+sqlite3_set_authorizer$", symbols, re.MULTILINE), (
        "Rebuilt validator does not contain SQLite authorization support"
    )


def test_adversarial_corpus():
    clean_files = [
        os.path.join(CLEAN_CORPUS_DIR, name)
        for name in os.listdir(CLEAN_CORPUS_DIR) if name.endswith(".sql")
    ]
    evil_files = [
        os.path.join(EVIL_CORPUS_DIR, name)
        for name in os.listdir(EVIL_CORPUS_DIR) if name.endswith(".sql")
    ]

    clean_failures = []
    evil_failures = []
    for clean_file in clean_files:
        try:
            result = subprocess.run(
                [VALIDATOR_PATH, clean_file], capture_output=True, text=True, timeout=5
            )
            output = result.stdout.strip()
            if output != "ACCEPT" or result.returncode != 0:
                clean_failures.append((os.path.basename(clean_file), output, result.returncode))
        except Exception as exc:
            clean_failures.append((os.path.basename(clean_file), str(exc), -1))

    for evil_file in evil_files:
        try:
            result = subprocess.run(
                [VALIDATOR_PATH, evil_file], capture_output=True, text=True, timeout=5
            )
            output = result.stdout.strip()
            if output != "REJECT" or result.returncode != 0:
                evil_failures.append((os.path.basename(evil_file), output, result.returncode))
        except Exception as exc:
            evil_failures.append((os.path.basename(evil_file), str(exc), -1))

    errors = []
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected:")
        errors.extend(f"  - {name} (output: {out!r}, exit: {rc})" for name, out, rc in clean_failures)
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted:")
        errors.extend(f"  - {name} (output: {out!r}, exit: {rc})" for name, out, rc in evil_failures)
    if errors:
        pytest.fail("\n".join(errors))


def test_generated_queries_with_uninformative_paths():
    safe_queries = [
        "SELECT id, name FROM datasets WHERE id >= -10 ORDER BY name;",
        "SELECT d.name, AVG(m.value) FROM datasets AS d LEFT JOIN measurements AS m ON m.dataset_id=d.id GROUP BY d.id, d.name;",
        "WITH RECURSIVE seq(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM seq WHERE x<4) SELECT SUM(x) FROM seq;",
        "WITH chosen AS (SELECT dataset_id, MAX(value) AS mx FROM measurements GROUP BY dataset_id) SELECT d.name, chosen.mx FROM chosen JOIN datasets d ON d.id=chosen.dataset_id;",
        "SELECT '-- DROP TABLE restricted_metadata' AS harmless, name FROM datasets;",
        "/* UPDATE measurements SET value=0; */ SELECT COUNT(*) FROM measurements;",
        "SELECT name AS restricted_metadata FROM datasets WHERE id IN (SELECT dataset_id FROM measurements WHERE value IS NOT NULL);",
        "SeLeCt COALESCE(MAX(value), 0.0) FROM measurements;",
    ]
    unsafe_queries = [
        "DROP TABLE datasets;",
        "INSERT INTO datasets VALUES (9, 'x');",
        "UPDATE measurements SET value=value+1;",
        "DELETE FROM measurements WHERE id=1;",
        "CREATE TABLE extra(x INTEGER);",
        "ALTER TABLE datasets ADD COLUMN secret TEXT;",
        "REPLACE INTO datasets(id,name) VALUES(1,'x');",
        "PRAGMA table_info(datasets);",
        "ATTACH DATABASE ':memory:' AS other;",
        "SELECT * FROM restricted_metadata;",
        "SELECT patient_name FROM \"restricted_metadata\";",
        "SELECT * FROM ReStRiCtEd_MeTaDaTa;",
        "WITH hidden AS (SELECT * FROM restricted_metadata) SELECT * FROM hidden;",
        "SELECT d.name FROM datasets d JOIN restricted_metadata r ON r.id=d.id;",
        "SELECT * FROM table_that_does_not_exist;",
        "SELECT FROM datasets;",
        "SELECT * FROM datasets; DROP TABLE measurements;",
        "WITH doomed AS (SELECT id FROM datasets) DELETE FROM measurements WHERE id IN (SELECT id FROM doomed);",
    ]

    with tempfile.TemporaryDirectory(prefix="sql_inputs_") as directory:
        cases = [(query, "ACCEPT") for query in safe_queries]
        cases += [(query, "REJECT") for query in unsafe_queries]
        for query, expected in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".dat")
            with open(path, "w") as output:
                output.write(query)
            for executable in (VALIDATOR_PATH, REBUILT_VALIDATOR):
                assert_classification(executable, path, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
