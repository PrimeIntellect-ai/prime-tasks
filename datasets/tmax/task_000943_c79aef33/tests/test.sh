#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
ENTRY_POINT = "/home/user/classifier/target/release/classifier"
COMPILER = "/app/astro_dsl_compiler"
DATABASE = "/app/astro_data.db"


def test_classifier_exists():
    assert os.path.exists(ENTRY_POINT), f"Classifier binary not found at {ENTRY_POINT}"
    assert os.path.isfile(ENTRY_POINT), f"{ENTRY_POINT} is not a file"
    assert os.access(ENTRY_POINT, os.X_OK), f"Classifier binary at {ENTRY_POINT} is not executable"
    with open(ENTRY_POINT, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Classifier at {ENTRY_POINT} is not a compiled executable"


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus missing or not a directory at {CLEAN_DIR}"
    assert os.path.isdir(EVIL_DIR), f"Evil corpus missing or not a directory at {EVIL_DIR}"

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith('.astro')]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith('.astro')]

    assert len(clean_files) > 0, "No clean files found in corpus"
    assert len(evil_files) > 0, "No evil files found in corpus"

    clean_failures = []
    for f in clean_files:
        res = subprocess.run([ENTRY_POINT, f], capture_output=True)
        if res.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        res = subprocess.run([ENTRY_POINT, f], capture_output=True)
        if res.returncode == 0:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def oracle_accepts(sql):
    match = re.search(r"\bLIMIT\s+([0-9]+)\b", sql, flags=re.IGNORECASE)
    if match is None or int(match.group(1)) > 100:
        return False

    with sqlite3.connect(DATABASE) as con:
        details = [str(row[3]).upper() for row in con.execute("EXPLAIN QUERY PLAN " + sql)]

    for table in ("STARS", "OBSERVATIONS"):
        if re.search(rf"\b(?:FROM|JOIN)\s+{table}\b", sql, flags=re.IGNORECASE):
            if any(re.search(rf"\bSCAN(?:\s+TABLE)?\s+{table}\b", d) for d in details):
                return False
            if not any(re.search(rf"\bSEARCH(?:\s+TABLE)?\s+{table}\b", d) for d in details):
                return False
    return True


def test_generated_queries_compiler_and_query_plan():
    assert subprocess.run([ENTRY_POINT], capture_output=True).returncode != 0
    extra = tempfile.NamedTemporaryFile(suffix=".astro", delete=False)
    extra.close()
    try:
        assert subprocess.run([ENTRY_POINT, extra.name, "unexpected"], capture_output=True).returncode != 0
    finally:
        os.unlink(extra.name)

    token = secrets.token_hex(12)
    work = tempfile.mkdtemp(prefix=f"classifier-generated-{token}-")
    compiler_backup = os.path.join(work, "compiler.backup")
    database_backup = os.path.join(work, "database.backup")
    control = os.path.join(work, "compiler-output.sql")
    log = os.path.join(work, "compiler-invocations.log")

    os.replace(COMPILER, compiler_backup)
    os.replace(DATABASE, database_backup)

    try:
        with sqlite3.connect(DATABASE) as con:
            con.executescript("""
                CREATE TABLE stars (id INTEGER PRIMARY KEY, mass REAL, name TEXT);
                CREATE TABLE observations (id INTEGER PRIMARY KEY, star_id INTEGER, brightness REAL);
                CREATE INDEX idx_obs_star ON observations(star_id);
                CREATE INDEX idx_stars_mass ON stars(mass);
            """)

        with open(COMPILER, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"printf '%s:%s\\n' \"$#\" \"$1\" >> '{log}'\n")
            f.write(f"cat '{control}'\n")
        os.chmod(COMPILER, 0o755)

        def run_generated(sql, expected):
            query_path = os.path.join(work, f"{secrets.token_hex(10)}.astro")
            with open(query_path, "w") as f:
                f.write("opaque-" + secrets.token_hex(24) + "\n")
            with open(control, "w") as f:
                f.write(sql + "\n")

            before = []
            if os.path.exists(log):
                with open(log) as f:
                    before = f.read().splitlines()

            derived = oracle_accepts(sql)
            assert derived == expected, f"Verifier fixture had unexpected plan: {sql}"
            result = subprocess.run([ENTRY_POINT, query_path], capture_output=True)

            with open(log) as f:
                after = f.read().splitlines()
            new_calls = after[len(before):]
            assert new_calls, "Classifier did not invoke /app/astro_dsl_compiler"
            assert all(call == f"1:{query_path}" for call in new_calls), \
                "Classifier did not invoke the compiler with exactly the submitted file"
            assert result.returncode == (0 if expected else 1), \
                f"Wrong classification for generated SQL {sql!r}: exit {result.returncode}"

        predicate = secrets.randbelow(10000) + 1
        clean_limit = secrets.randbelow(100) + 1
        evil_limit = secrets.randbelow(400) + 101

        stars_sql = f"SELECT * FROM stars WHERE mass > {predicate} LIMIT {clean_limit};"
        run_generated(stars_sql, True)

        with sqlite3.connect(DATABASE) as con:
            con.execute("DROP INDEX idx_stars_mass")
        run_generated(stars_sql, False)
        assert not oracle_accepts(stars_sql), "Classifier modified the database plan"
        with sqlite3.connect(DATABASE) as con:
            con.execute("CREATE INDEX idx_stars_mass ON stars(mass)")

        obs_sql = f"SELECT * FROM observations WHERE star_id = {predicate} LIMIT 100;"
        run_generated(obs_sql, True)
        with sqlite3.connect(DATABASE) as con:
            con.execute("DROP INDEX idx_obs_star")
        run_generated(obs_sql, False)
        assert not oracle_accepts(obs_sql), "Classifier modified the database plan"
        with sqlite3.connect(DATABASE) as con:
            con.execute("CREATE INDEX idx_obs_star ON observations(star_id)")

        run_generated(f"SELECT * FROM stars WHERE mass > {predicate} LIMIT {evil_limit};", False)
        run_generated(f"SELECT * FROM stars WHERE mass > {predicate};", False)
        run_generated(f"SELECT * FROM stars WHERE mass > {predicate} LIMIT 100;", True)
    finally:
        for suffix in ("", "-wal", "-shm"):
            path = DATABASE + suffix
            if os.path.exists(path):
                os.unlink(path)
        if os.path.exists(database_backup):
            os.replace(database_backup, DATABASE)
        if os.path.exists(COMPILER):
            os.unlink(COMPILER)
        if os.path.exists(compiler_backup):
            os.replace(compiler_backup, COMPILER)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
