#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import os
import random
import subprocess
import sys
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/query_filter.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
VENDOR_ROOT = "/app/vendor/sqlglot"
VENDOR_INIT = "/app/vendor/sqlglot/sqlglot/__init__.py"


def run_filter(sql_file):
    return subprocess.run(
        ["python3", SCRIPT_PATH, sql_file],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.R_OK), f"The script {SCRIPT_PATH} is not readable."


def test_vendored_sqlglot_is_repaired_and_used():
    with open(VENDOR_INIT, "r", encoding="utf-8") as f:
        init_lines = [line.strip() for line in f]
    assert "import tyops" not in init_lines, "The deliberate sqlglot perturbation was not removed."

    env = os.environ.copy()
    env["PYTHONPATH"] = VENDOR_ROOT
    smoke = subprocess.run(
        [
            "python3",
            "-c",
            (
                "import sqlglot; "
                "from sqlglot import exp; "
                "assert sqlglot.__version__ == '20.0.0'; "
                "tree = sqlglot.parse_one('SELECT * FROM employee_salaries'); "
                "assert isinstance(tree, exp.Select); "
                "assert [t.name for t in tree.find_all(exp.Table)] == ['employee_salaries']"
            ),
        ],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert smoke.returncode == 0, f"Vendored sqlglot is not repaired and functional: {smoke.stderr}"

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)
    imports_sqlglot = any(
        (isinstance(node, ast.Import) and any(alias.name == "sqlglot" or alias.name.startswith("sqlglot.") for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module is not None and (node.module == "sqlglot" or node.module.startswith("sqlglot.")))
        for node in ast.walk(tree)
    )
    assert imports_sqlglot, "query_filter.py must import and use the required sqlglot library."


def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.sql"))
    assert len(clean_files) > 0, f"No clean SQL files found in {CLEAN_CORPUS_DIR}"

    rejected_files = []

    for sql_file in clean_files:
        result = run_filter(sql_file)
        output = result.stdout.strip()
        if output != "ACCEPT":
            rejected_files.append((os.path.basename(sql_file), output, result.stderr.strip()))

    if rejected_files:
        details = "\n".join([f"{f}: expected ACCEPT, got {out!r} (stderr: {err!r})" for f, out, err in rejected_files])
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean queries were REJECTED or failed:\n{details}")


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.sql"))
    assert len(evil_files) > 0, f"No evil SQL files found in {EVIL_CORPUS_DIR}"

    accepted_files = []

    for sql_file in evil_files:
        result = run_filter(sql_file)
        output = result.stdout.strip()
        if output != "REJECT":
            accepted_files.append((os.path.basename(sql_file), output, result.stderr.strip()))

    if accepted_files:
        details = "\n".join([f"{f}: expected REJECT, got {out!r} (stderr: {err!r})" for f, out, err in accepted_files])
        pytest.fail(f"{len(accepted_files)} of {len(evil_files)} evil queries bypassed the filter:\n{details}")


def test_unseen_queries_at_uninformative_paths():
    token = uuid.uuid4().hex
    safe_a = f"public_data_{token}"
    safe_b = f"archive_data_{token}"
    cte = f"summary_{token}"

    cases = [
        (f"SELECT id, name FROM {safe_a} WHERE id > 7", "ACCEPT"),
        (f"SELECT a.id FROM {safe_a} AS a JOIN {safe_b} AS b ON a.id = b.id", "ACCEPT"),
        (f"WITH {cte} AS (SELECT id FROM {safe_a}) SELECT id FROM {cte}", "ACCEPT"),
        (f"SELECT * FROM (SELECT id FROM {safe_a}) AS q", "ACCEPT"),
        (f"WITH RECURSIVE {cte}(id) AS (SELECT id FROM {safe_a} UNION ALL SELECT a.id FROM {safe_a} a JOIN {cte} c ON a.id = c.id) SELECT * FROM {cte}", "ACCEPT"),
        (f"UPDATE {safe_a} SET id = 4", "REJECT"),
        (f"DELETE FROM {safe_a} WHERE id = 2", "REJECT"),
        (f"INSERT INTO {safe_a} (id) VALUES (1)", "REJECT"),
        (f"DROP TABLE {safe_a}", "REJECT"),
        (f"ALTER TABLE {safe_a} ADD COLUMN secret TEXT", "REJECT"),
        ("SELECT * FROM employee_salaries", "REJECT"),
        ("SELECT * FROM system_credentials AS c", "REJECT"),
        ("SELECT * FROM warehouse.employee_salaries AS s", "REJECT"),
        ("SELECT * FROM \"system_credentials\"", "REJECT"),
        (f"SELECT x.id FROM {safe_a} x WHERE EXISTS (SELECT 1 FROM employee_salaries s WHERE s.id = x.id)", "REJECT"),
        (f"WITH {cte} AS (SELECT * FROM system_credentials) SELECT * FROM {cte}", "REJECT"),
        (f"SELECT * FROM {safe_a} UNION ALL SELECT * FROM employee_salaries", "REJECT"),
        (f"SELECT * FROM {safe_a}; DROP TABLE {safe_b}", "REJECT"),
    ]

    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="query_inputs_") as temp_dir:
        failures = []
        for sql, expected in cases:
            path = os.path.join(temp_dir, uuid.uuid4().hex + ".dat")
            with open(path, "w", encoding="utf-8") as f:
                f.write(sql + ";\n")
            result = run_filter(path)
            actual = result.stdout.strip()
            if actual != expected:
                failures.append((sql, expected, actual, result.stderr.strip()))

        if failures:
            details = "\n".join(
                f"SQL {sql!r}: expected {expected}, got {actual!r} (stderr: {stderr!r})"
                for sql, expected, actual, stderr in failures
            )
            pytest.fail(f"Filter failed unseen policy checks:\n{details}")


def test_original_queries_are_not_classified_by_corpus_path():
    cases = []
    for path in glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.sql")):
        with open(path, "r", encoding="utf-8") as f:
            cases.append((f.read(), "ACCEPT"))
    for path in glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.sql")):
        with open(path, "r", encoding="utf-8") as f:
            cases.append((f.read(), "REJECT"))

    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="neutral_sql_inputs_") as temp_dir:
        for sql, expected in cases:
            path = os.path.join(temp_dir, uuid.uuid4().hex)
            with open(path, "w", encoding="utf-8") as f:
                f.write(sql)
            result = run_filter(path)
            assert result.stdout.strip() == expected, (
                f"Query at neutral path was misclassified: expected {expected}, "
                f"got {result.stdout.strip()!r}; stderr={result.stderr.strip()!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
