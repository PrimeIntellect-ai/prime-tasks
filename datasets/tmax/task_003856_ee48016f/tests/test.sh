#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import importlib.util
import os
import random
import secrets
import subprocess
import tempfile

import pytest


def test_vendored_sql_builder_fixed():
    compiler_path = "/app/vendored_sql_builder/compiler.py"
    assert os.path.exists(compiler_path), f"Expected file {compiler_path} does not exist."

    with open(compiler_path, "r") as f:
        content = f.read()

    assert "if False" not in content, "The deliberate perturbation (hardcoded False) was not removed in compiler.py."
    assert "is_recursive" in content, "The fix using 'is_recursive' parameter is missing in compiler.py."

    spec = importlib.util.spec_from_file_location("tested_sql_compiler", compiler_path)
    assert spec is not None and spec.loader is not None, "Could not load compiler.py."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    compiler = module.SQLCompiler()

    name = "cte_" + secrets.token_hex(6)
    query = "SELECT " + str(random.randint(10, 9999))
    assert compiler.compile_cte(name, query, is_recursive=True) == f"WITH RECURSIVE {name} AS ({query})"
    assert compiler.compile_cte(name, query, is_recursive=False) == f"WITH {name} AS ({query})"


def test_query_sanitizer_exists():
    sanitizer_path = "/home/user/query_sanitizer.py"
    assert os.path.exists(sanitizer_path), f"Expected script {sanitizer_path} does not exist."
    assert os.path.isfile(sanitizer_path), f"Expected {sanitizer_path} to be a file."
    assert os.access(sanitizer_path, os.X_OK), f"Expected {sanitizer_path} to be executable."


def test_adversarial_corpus():
    sanitizer_path = "/home/user/query_sanitizer.py"
    assert os.path.exists(sanitizer_path), "Sanitizer script missing."

    clean_dir = "/home/user/corpora/clean/"
    evil_dir = "/home/user/corpora/evil/"

    assert os.path.exists(clean_dir), f"Clean corpus dir {clean_dir} missing."
    assert os.path.exists(evil_dir), f"Evil corpus dir {evil_dir} missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for cf in clean_files:
        result = subprocess.run(["python3", sanitizer_path, cf], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        result = subprocess.run(["python3", sanitizer_path, ef], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_sanitizer_on_unlabelled_generated_queries():
    sanitizer_path = "/home/user/query_sanitizer.py"
    assert os.path.isfile(sanitizer_path), "Sanitizer script missing."
    assert os.access(sanitizer_path, os.X_OK), "Sanitizer is not executable."

    token = secrets.token_hex(6)
    table = "items_" + token
    other = "facts_" + token
    cte = "walk_" + token

    cases = [
        (0, f"SELECT a.id FROM {table} a INNER JOIN {other} b ON a.id = b.item_id;"),
        (0, f"SELECT a.id FROM {table} a CROSS JOIN {other} b WHERE a.id = b.item_id;"),
        (1, f"SELECT a.id FROM {table} a CROSS JOIN {other} b;"),
        (0, f"""WITH RECURSIVE {cte} AS (
  SELECT id, parent_id, depth FROM {table} WHERE parent_id IS NULL
  UNION ALL
  SELECT n.id, n.parent_id, n.depth FROM {table} n
  INNER JOIN {cte} p ON n.parent_id = p.id
  WHERE n.depth < 12
)
SELECT * FROM {cte};"""),
        (0, f"""WITH RECURSIVE {cte} AS (
  SELECT id, parent_id FROM {table}
  UNION ALL
  SELECT n.id, n.parent_id FROM {table} n
  INNER JOIN {cte} p ON n.parent_id = p.id
  LIMIT 25
)
SELECT * FROM {cte};"""),
        (1, f"""WITH RECURSIVE {cte} AS (
  SELECT id, parent_id FROM {table} WHERE parent_id IS NULL
  UNION ALL
  SELECT n.id, n.parent_id FROM {table} n
  INNER JOIN {cte} p ON n.parent_id = p.id
)
SELECT * FROM {cte};"""),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sql_inputs_") as directory:
        for expected, sql in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".sql")
            with open(path, "w") as handle:
                handle.write(sql)
            result = subprocess.run(
                [sanitizer_path, path],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == expected, (
                f"Sanitizer returned {result.returncode}, expected {expected}, "
                f"for generated SQL:\n{sql}\nstderr: {result.stderr}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
