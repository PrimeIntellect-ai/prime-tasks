#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_SQLITE=/tmp/verifier_sqlite3.real
SQLITE_LOG=/tmp/verifier_sqlite3.log
cp /usr/bin/sqlite3 "$REAL_SQLITE"
trap 'cp "$REAL_SQLITE" /usr/bin/sqlite3 2>/dev/null || true; chmod 755 /usr/bin/sqlite3 2>/dev/null || true' EXIT

cat << 'WRAPPER_EOF' > /usr/bin/sqlite3
#!/bin/bash
real=/tmp/verifier_sqlite3.real
log=/tmp/verifier_sqlite3.log
tmp=$(mktemp)
cat > "$tmp"
{
    echo '--- invocation ---'
    printf 'ARG=%s\n' "$@"
    echo 'STDIN_BEGIN'
    cat "$tmp"
    echo 'STDIN_END'
} >> "$log"
"$real" "$@" < "$tmp"
status=$?
rm -f "$tmp"
exit "$status"
WRAPPER_EOF
chmod 755 /usr/bin/sqlite3
: > "$SQLITE_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
import uuid

import pytest

SCRIPT = "/home/user/detect_deadlocks.sh"
INPUT = "/home/user/waits.csv"
OUTPUT = "/home/user/deadlocks.json"
SQLITE_LOG = "/tmp/verifier_sqlite3.log"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def expected_cycles(edges):
    graph = {}
    nodes = set()
    for waiting, blocking, _resource in edges:
        nodes.update((waiting, blocking))
        graph.setdefault(waiting, set()).add(blocking)

    result = []
    for start in nodes:
        stack = list(graph.get(start, ()))
        seen = set()
        cyclic = False
        while stack:
            node = stack.pop()
            if node == start:
                cyclic = True
                break
            if node in seen:
                continue
            seen.add(node)
            stack.extend(graph.get(node, ()))
        if cyclic:
            result.append(start)
    return sorted(result)


def write_csv(edges):
    with open(INPUT, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["waiting_trx", "blocking_trx", "resource"])
        writer.writerows(edges)


def run_and_check(edges, expected=None):
    write_csv(edges)
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    open(SQLITE_LOG, "w").close()

    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist after running the script."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."

    try:
        with open(OUTPUT) as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {OUTPUT} does not contain valid JSON: {exc}")

    derived = expected_cycles(edges)
    if expected is not None:
        assert derived == expected
    assert isinstance(data, list), f"JSON output should be a list, got {type(data).__name__}."
    assert data == derived, f"Expected deadlocked transactions {derived}, got {data}."
    assert data == sorted(data), "The JSON array is not sorted alphabetically."
    assert all(isinstance(item, str) for item in data), "Every JSON array item must be a string."

    with open(SQLITE_LOG, errors="replace") as f:
        sql = f.read()
    assert re.search(r"\bwith\s+recursive\b", sql, re.IGNORECASE), (
        "The executed SQLite commands did not contain a recursive CTE."
    )
    assert re.search(r"\block_waits\b", sql, re.IGNORECASE), (
        "The executed SQLite commands did not use the required lock_waits table."
    )
    assert re.search(r"\bcreate\b[\s\S]{0,120}\btable\b[\s\S]{0,120}\block_waits\b", sql, re.IGNORECASE), (
        "The script did not create the required lock_waits table in SQLite."
    )


def test_json_output_exists_and_correct_after_execution():
    assert os.path.isfile(SCRIPT)
    assert os.access(SCRIPT, os.X_OK)
    with open(SCRIPT, errors="replace") as f:
        source = f.read()
    assert re.search(r"(^|/)waits\.csv\b", source), "The script does not reference waits.csv."
    assert re.search(r"mktemp|:memory:|/tmp/|TMPDIR", source, re.IGNORECASE), (
        "The script does not appear to use a temporary SQLite database."
    )

    with open(INPUT, "rb") as f:
        original = f.read()

    try:
        original_edges = [
            ("T100", "T101", "users"),
            ("T101", "T102", "orders"),
            ("T102", "T100", "inventory"),
            ("T103", "T104", "audit_log"),
            ("T104", "T105", "sessions"),
            ("T106", "T106", "self_wait"),
            ("T107", "T108", "cache"),
            ("T108", "T109", "cache"),
            ("T109", "T107", "cache"),
            ("T110", "T101", "users"),
        ]
        run_and_check(
            original_edges,
            ["T100", "T101", "T102", "T106", "T107", "T108", "T109"],
        )

        token = uuid.uuid4().hex
        names = [f"V_{token}_{i:02d}" for i in range(12)]
        dynamic_edges = [
            (names[0], names[1], "r1"),
            (names[1], names[2], "r2"),
            (names[2], names[0], "r3"),
            (names[3], names[3], "self"),
            (names[4], names[0], "feeds_cycle"),
            (names[1], names[5], "leaves_cycle"),
            (names[6], names[7], "pair_a"),
            (names[7], names[6], "pair_b"),
            (names[8], names[9], "acyclic_a"),
            (names[9], names[10], "acyclic_b"),
        ]
        run_and_check(dynamic_edges)

        no_cycle_edges = [
            (names[0], names[1], "a"),
            (names[1], names[2], "b"),
            (names[3], names[2], "c"),
        ]
        run_and_check(no_cycle_edges, [])
    finally:
        with open(INPUT, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
