#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import json
import os
import random
import secrets
import stat
import string
import subprocess
import sys
import tempfile

import pytest

PACKAGE_DIR = "/app/sql-graph-proj-1.0.0"
FILTER_SCRIPT = "/home/user/sql_filter.py"


def test_vendored_package_installed_and_fixed():
    compiler_path = os.path.join(PACKAGE_DIR, "sql_graph_proj", "compiler.py")
    assert os.path.isfile(compiler_path), f"Compiler file missing: {compiler_path}"

    with open(compiler_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert " INNER JOIN " in content, "The ' CROSS JOIN ' bug was not fixed to ' INNER JOIN ' in compiler.py."
    assert " CROSS JOIN " not in content, "The ' CROSS JOIN ' bug is still present in compiler.py."

    # Actually verify that the repaired package can be installed as requested.
    install = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", ".", "--disable-pip-version-check"],
        cwd=PACKAGE_DIR,
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert install.returncode == 0, f"pip install -e . failed:\n{install.stdout}\n{install.stderr}"

    # Use a fresh interpreter so the editable installation is loaded, then exercise
    # build_query rather than trusting source keywords.
    probe = subprocess.run(
        [
            sys.executable,
            "-c",
            "import json, sql_graph_proj.compiler as c; "
            "print(json.dumps({'query': c.build_query(), 'file': c.__file__}))",
        ],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert probe.returncode == 0, f"Installed package is not importable:\n{probe.stderr}"
    try:
        result = json.loads(probe.stdout.strip().splitlines()[-1])
    except Exception as exc:
        pytest.fail(f"Could not inspect installed compiler: {exc}; output={probe.stdout!r}")

    assert os.path.realpath(result["file"]).startswith(os.path.realpath(PACKAGE_DIR) + os.sep)
    assert result["query"] == "SELECT * FROM table1 INNER JOIN table2", \
        f"build_query() returned incorrect SQL: {result['query']!r}"


def test_setup_py_fixed():
    setup_path = os.path.join(PACKAGE_DIR, "setup.py")
    assert os.path.isfile(setup_path), f"Setup file missing: {setup_path}"

    with open(setup_path, "r") as f:
        content = f.read()

    # Preserve the original assertion in addition to the real installation test.
    assert "sqlite3>=4.0" not in content, "The invalid 'sqlite3>=4.0' dependency is still in setup.py."


def run_filter(path, direct=False):
    command = [FILTER_SCRIPT, path] if direct else [sys.executable, FILTER_SCRIPT, path]
    return subprocess.run(command, capture_output=True, timeout=10).returncode


def test_adversarial_sql_filter_on_corpora():
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script missing: {FILTER_SCRIPT}"
    mode = os.stat(FILTER_SCRIPT).st_mode
    assert mode & stat.S_IXUSR, "Filter script is not executable by its owner."

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    assert os.path.isdir(clean_dir), f"Clean corpus missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".sql")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".sql")]
    assert clean_files, "No clean corpus files found."
    assert evil_files, "No evil corpus files found."

    clean_failures = [os.path.basename(p) for p in clean_files if run_filter(p) != 0]
    evil_failures = [os.path.basename(p) for p in evil_files if run_filter(p) != 1]

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean rejected: {', '.join(clean_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_adversarial_sql_filter_on_generated_queries():
    # Fresh identifiers, paths, capitalization, and whitespace prevent solutions
    # that memorize the four visible corpus files while retaining the same SQL rules.
    def ident():
        return "t_" + secrets.token_hex(6)

    a, b, c, d, e, f, g, h = [ident() for _ in range(8)]
    cases = [
        (f"SELECT * FROM {a} INNER JOIN {b} ON {a}.id = {b}.owner_id;\n", 0),
        (f"select {c}.id from {c}\nJoIn {d} oN {c}.id={d}.id;\n", 0),
        (f"SELECT *\nFROM {e}, {f};\n", 1),
        (f"select * from {g}\nCrOsS JoIn {h};\n", 1),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sql_cases_" + secrets.token_hex(5) + "_") as temp_dir:
        written = []
        for sql, expected in cases:
            name = secrets.token_hex(12) + ".sql"
            path = os.path.join(temp_dir, name)
            with open(path, "w") as out:
                out.write(sql)
            written.append((path, expected, sql))

        random.SystemRandom().shuffle(written)
        for path, expected, sql in written:
            actual = run_filter(path, direct=True)
            assert actual == expected, \
                f"Filter returned {actual}, expected {expected}, for generated SQL: {sql!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
