#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import subprocess
import time
import uuid


def test_fast_query_script_exists():
    script_path = "/home/user/fast_query.sh"
    assert os.path.exists(script_path), f"Script missing at {script_path}"
    assert os.path.isfile(script_path), f"Script is not a file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_fast_query_accuracy_performance_and_sqlite_use(tmp_path):
    script_path = "/home/user/fast_query.sh"
    oracle_path = "/app/citation_oracle"
    edgelist_file = tmp_path / "edgelist.txt"
    queries_file = tmp_path / "queries.txt"

    # Use fresh, unpredictable input so fixed outputs cannot pass.
    rng = random.SystemRandom()
    nodes = 1000
    edges = 10000
    with open(edgelist_file, "w") as f:
        for _ in range(edges):
            f.write(f"{rng.randint(1, nodes)} {rng.randint(1, nodes)}\n")

    queries = []
    with open(queries_file, "w") as f:
        for _ in range(100):
            u = rng.randint(1, nodes)
            v = rng.randint(1, nodes)
            queries.append((u, v))
            f.write(f"{u} {v}\n")

    ground_truth = []
    for u, v in queries:
        result = subprocess.run(
            [oracle_path, str(edgelist_file), str(u), str(v)],
            capture_output=True,
            text=True,
            check=True,
        )
        ground_truth.append(result.stdout.strip())

    # Interpose the installed sqlite3 executable and record SQL actually sent to it.
    sqlite_path = "/usr/bin/sqlite3"
    real_sqlite = f"/tmp/sqlite3.real.{uuid.uuid4().hex}"
    audit_path = f"/tmp/sqlite-audit.{uuid.uuid4().hex}"
    os.replace(sqlite_path, real_sqlite)
    wrapper = f'''#!/bin/bash
set -e
tmp=$(mktemp)
cat > "$tmp"
{{
  printf '%s\\n' '--- sqlite invocation ---'
  printf 'arg: %s\\n' "$@"
  cat "$tmp"
  printf '\\n'
}} >> {shlex.quote(audit_path)}
exec {shlex.quote(real_sqlite)} "$@" < "$tmp"
'''
    try:
        with open(sqlite_path, "w") as f:
            f.write(wrapper)
        os.chmod(sqlite_path, 0o755)

        start_time = time.monotonic()
        try:
            result = subprocess.run(
                ["bash", script_path, str(edgelist_file), str(queries_file)],
                capture_output=True,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired as exc:
            raise AssertionError("Script exceeded the performance limit") from exc
        runtime = time.monotonic() - start_time
    finally:
        if os.path.exists(sqlite_path):
            os.unlink(sqlite_path)
        os.replace(real_sqlite, sqlite_path)

    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"

    outputs = result.stdout.strip().split("\n")
    assert len(outputs) == len(ground_truth), (
        f"Expected {len(ground_truth)} output lines, got {len(outputs)}"
    )
    for i, (out, truth) in enumerate(zip(outputs, ground_truth)):
        assert out == truth, (
            f"Query {i + 1} ({queries[i][0]} -> {queries[i][1]}): "
            f"expected {truth}, got {out}"
        )

    threshold = 3.0
    assert runtime <= threshold, f"Runtime {runtime:.2f}s exceeded {threshold}s threshold."

    assert os.path.exists(audit_path), "The script did not execute sqlite3"
    with open(audit_path, errors="replace") as f:
        sql_audit = f.read()
    normalized = sql_audit.lower()
    assert re.search(r"\bwith\s+recursive\b", normalized), (
        "No recursive CTE was actually submitted to sqlite3"
    )
    assert re.search(r"\bcreate\s+(?:unique\s+)?index\b", normalized), (
        "No index was actually created through sqlite3"
    )
    assert (".import" in normalized or re.search(r"\binsert\s+into\b", normalized)), (
        "No edgelist data load was submitted to sqlite3"
    )


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
