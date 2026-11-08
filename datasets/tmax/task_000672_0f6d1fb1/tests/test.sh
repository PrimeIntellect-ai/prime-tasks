#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import sqlite3
import subprocess
import tempfile


def test_build_script_fixed():
    build_script = '/app/sqlite-src/build.sh'
    assert os.path.isfile(build_script), f"{build_script} is missing."
    with open(build_script, 'r') as f:
        content = f.read()
    assert '-DSQLITE_OMIT_CTE' not in content, "The -DSQLITE_OMIT_CTE flag was not removed from /app/sqlite-src/build.sh"


def test_checker_exists_and_executable():
    checker_path = '/home/user/checker'
    assert os.path.isfile(checker_path), f"Checker executable not found at {checker_path}"
    assert os.access(checker_path, os.X_OK), f"Checker at {checker_path} is not executable"
    with open(checker_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Checker must be a compiled executable"
    assert os.path.isfile('/home/user/checker.c'), "C source not found at /home/user/checker.c"


def test_adversarial_corpus():
    checker_path = '/home/user/checker'
    clean_dir = '/home/user/corpora/clean/'
    evil_dir = '/home/user/corpora/evil/'

    clean_files = glob.glob(os.path.join(clean_dir, '*.db'))
    evil_files = glob.glob(os.path.join(evil_dir, '*.db'))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    failed_clean = []
    for cf in clean_files:
        res = subprocess.run([checker_path, cf], capture_output=True, text=True)
        if res.returncode != 0 or res.stdout.strip() != 'CLEAN':
            failed_clean.append(os.path.basename(cf))

    failed_evil = []
    for ef in evil_files:
        res = subprocess.run([checker_path, ef], capture_output=True, text=True)
        if res.returncode != 1 or res.stdout.strip() != 'EVIL':
            failed_evil.append(os.path.basename(ef))

    error_msgs = []
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified (failed to accept): {', '.join(failed_clean)}")

    assert not failed_clean and not failed_evil, "\n".join(error_msgs)


def test_rebuilt_library_supports_recursive_ctes():
    build = subprocess.run(
        ['bash', 'build.sh'], cwd='/app/sqlite-src', capture_output=True, text=True,
        timeout=120
    )
    assert build.returncode == 0, f"SQLite build failed:\n{build.stdout}\n{build.stderr}"
    archive = '/app/sqlite-src/libsqlite3.a'
    assert os.path.isfile(archive) and os.path.getsize(archive) > 0, "libsqlite3.a was not built"

    probe_source = r'''
#include "sqlite3.h"
int main(void) {
    sqlite3 *db = 0;
    sqlite3_stmt *st = 0;
    int rc = sqlite3_open(":memory:", &db);
    if (rc != SQLITE_OK) return 2;
    rc = sqlite3_prepare_v2(db,
        "WITH RECURSIVE cnt(x) AS (VALUES(1) UNION ALL "
        "SELECT x+1 FROM cnt WHERE x<5) SELECT max(x) FROM cnt;",
        -1, &st, 0);
    if (rc != SQLITE_OK) return 3;
    rc = sqlite3_step(st);
    int ok = rc == SQLITE_ROW && sqlite3_column_int(st, 0) == 5;
    sqlite3_finalize(st);
    sqlite3_close(db);
    return ok ? 0 : 4;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, 'probe.c')
        exe = os.path.join(td, 'probe')
        with open(src, 'w') as f:
            f.write(probe_source)
        cc = subprocess.run([
            'gcc', '-I/app/sqlite-src', src, archive,
            '-lpthread', '-ldl', '-lm', '-o', exe
        ], capture_output=True, text=True, timeout=120)
        assert cc.returncode == 0, f"Could not link against rebuilt libsqlite3.a:\n{cc.stderr}"
        run = subprocess.run([exe], capture_output=True, text=True, timeout=10)
        assert run.returncode == 0, "Rebuilt libsqlite3.a does not execute recursive CTEs"


def _make_cases():
    rng = random.SystemRandom()
    cases = []

    for n in (0, 1, 5, 12, 19):
        nodes = rng.sample(range(10000, 2000000000), n)
        edges = []
        for i in range(n):
            for j in range(i + 1, n):
                if rng.random() < 0.24:
                    edges.append((nodes[i], nodes[j]))
        cases.append(('CLEAN', edges))

    node = rng.randrange(10000, 2000000000)
    cases.append(('EVIL', [(node, node)]))

    for n in (2, 3, 7, 13):
        nodes = rng.sample(range(10000, 2000000000), n + 3)
        edges = [(nodes[i], nodes[(i + 1) % n]) for i in range(n)]
        edges.extend([(nodes[n], nodes[n + 1]), (nodes[n + 1], nodes[n + 2])])
        cases.append(('EVIL', edges))

    rng.shuffle(cases)
    return cases


def _write_database(path, edges):
    if os.path.exists(path):
        os.unlink(path)
    con = sqlite3.connect(path)
    try:
        con.execute('CREATE TABLE citations (source_id INT, target_id INT)')
        con.executemany('INSERT INTO citations VALUES (?, ?)', edges)
        con.commit()
    finally:
        con.close()


def _exercise(executable, cases, database_path):
    random.SystemRandom().shuffle(cases)
    for expected, edges in cases:
        _write_database(database_path, edges)
        res = subprocess.run(
            [executable, database_path], capture_output=True, text=True, timeout=10
        )
        wanted_rc = 0 if expected == 'CLEAN' else 1
        assert res.returncode == wanted_rc, (
            f"Generated {expected} graph returned {res.returncode}; "
            f"stdout={res.stdout!r}, stderr={res.stderr!r}"
        )
        assert res.stdout in (expected, expected + '\n'), (
            f"Generated {expected} graph produced unexpected output {res.stdout!r}"
        )


def test_generated_graphs_and_vendored_link():
    cases = _make_cases()
    with tempfile.TemporaryDirectory(prefix='graph-check-') as td:
        database_path = os.path.join(td, 'input.db')

        # Reuse one neutral, unpredictable path for both classifications so the
        # result cannot be inferred from corpus directories or filenames.
        _exercise('/home/user/checker', list(cases), database_path)

        rebuilt_checker = os.path.join(td, 'checker-from-source')
        cc = subprocess.run([
            'gcc', '-O2', '-I/app/sqlite-src', '/home/user/checker.c',
            '/app/sqlite-src/libsqlite3.a', '-lpthread', '-ldl', '-lm',
            '-o', rebuilt_checker
        ], capture_output=True, text=True, timeout=120)
        assert cc.returncode == 0, (
            "checker.c could not be linked against the rebuilt vendored library:\n"
            + cc.stderr
        )
        _exercise(rebuilt_checker, list(cases), database_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
