#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import random
import shutil
import sqlite3
import stat
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/filter.sh"
COMPILER_PATH = "/app/graph_compiler"
DB_PATH = "/app/graph.db"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def run_filter(path):
    return subprocess.run([SCRIPT_PATH, path], capture_output=True, timeout=10)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} missing."
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} missing."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".gql")]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".gql")]

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    bypassed_evil = []
    for f in evil_files:
        result = run_filter(f)
        if result.returncode != 1:
            bypassed_evil.append(os.path.basename(f))

    modified_clean = []
    for f in clean_files:
        result = run_filter(f)
        if result.returncode != 0:
            modified_clean.append(os.path.basename(f))

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")

    assert not errors, " | ".join(errors)


def explain_uses_stale(sql):
    con = sqlite3.connect(DB_PATH)
    try:
        rows = con.execute("EXPLAIN QUERY PLAN " + sql).fetchall()
    finally:
        con.close()
    plan = "\n".join(str(col) for row in rows for col in row)
    return "idx_stale_edges" in plan


def test_hidden_queries_and_compiler_invocation():
    assert os.path.isfile(COMPILER_PATH), "Compiler is missing."
    assert os.access(COMPILER_PATH, os.X_OK), "Compiler is not executable."

    rng = random.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="gql-hidden-")
    backup = os.path.join(workdir, "compiler-original")
    log_path = os.path.join(workdir, "compiler-calls.log")
    shutil.copy2(COMPILER_PATH, backup)

    stale_sql = "SELECT dst FROM edges WHERE src=137 AND type='Type';"
    safe_sql = "SELECT dst FROM edges WHERE src=137 AND dst=241;"
    assert explain_uses_stale(stale_sql), "Verifier stale query did not use idx_stale_edges."
    assert not explain_uses_stale(safe_sql), "Verifier safe query unexpectedly used idx_stale_edges."

    cases = []
    labels = [True, False] * 4
    rng.shuffle(labels)
    mapping = {}
    for i, stale in enumerate(labels):
        token = base64.urlsafe_b64encode(os.urandom(36)).decode("ascii")
        content = f"OPAQUE QUERY {token} VALUE {rng.randrange(1, 10**9)}\n".encode()
        path = os.path.join(workdir, f"query_{i}_{rng.randrange(1, 10**9)}.gql")
        with open(path, "wb") as f:
            f.write(content)
        sql = stale_sql if stale else safe_sql
        mapping[base64.b64encode(content).decode("ascii")] = sql
        cases.append((path, content, stale))

    wrapper = f'''#!/usr/bin/env python3
import base64, hashlib, json, subprocess, sys
mapping = json.loads({json.dumps(json.dumps(mapping))})
data = sys.stdin.buffer.read()
with open({log_path!r}, "a", encoding="utf-8") as log:
    log.write(hashlib.sha256(data).hexdigest() + "\\n")
key = base64.b64encode(data).decode("ascii")
if key in mapping:
    sys.stdout.write(mapping[key] + "\\n")
    sys.exit(0)
result = subprocess.run([{backup!r}], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
'''

    try:
        with open(COMPILER_PATH, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(COMPILER_PATH, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                                stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        errors = []
        for path, content, stale in cases:
            result = run_filter(path)
            expected = 1 if stale else 0
            if result.returncode != expected:
                errors.append(f"{os.path.basename(path)} returned {result.returncode}, expected {expected}")

        seen = set()
        if os.path.exists(log_path):
            with open(log_path, encoding="utf-8") as f:
                seen = {line.strip() for line in f if line.strip()}
        missing_calls = [os.path.basename(path) for path, content, _ in cases
                         if hashlib.sha256(content).hexdigest() not in seen]
        if missing_calls:
            errors.append("compiler was not invoked with: " + ", ".join(missing_calls))

        assert not errors, " | ".join(errors)
    finally:
        shutil.copy2(backup, COMPILER_PATH)
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
