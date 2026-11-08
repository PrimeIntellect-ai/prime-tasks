#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid

import pytest

TRACE = "/home/user/trace.py"
SUMMARIZE = "/home/user/summarize.sh"
DB = "/home/user/research.db"
SUMMARY = "/home/user/raw_data_summary.txt"


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, timeout=15, **kwargs)


def test_trace_script_exists_and_uses_cte():
    assert os.path.isfile(TRACE), f"Python script {TRACE} is missing."

    with open(TRACE, "r") as f:
        content = f.read().lower()

    # Preserve the original source-level assertion. Execution tests below verify
    # that a parameterized recursive CTE is actually run.
    assert "with recursive" in content or "with " in content, \
        "The script /home/user/trace.py does not appear to use a Recursive CTE as requested."


def test_summarize_script_exists():
    assert os.path.isfile(SUMMARIZE), f"Bash script {SUMMARIZE} is missing."


def test_raw_data_summary_output():
    assert os.path.isfile(SUMMARY), f"Output file {SUMMARY} was not created."

    with open(SUMMARY, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Raw Data D content.",
        "Raw Data E content.",
        "Raw Data F content."
    ]

    unique_lines = sorted(list(set(lines)))
    assert unique_lines == expected_lines, \
        f"Expected unique lines {expected_lines}, but got {unique_lines} in {SUMMARY}."


def test_trace_script_functionality():
    result = run(["python3", TRACE, "Final_Analysis_V3"])
    assert result.returncode == 0, f"Running {TRACE} failed with error: {result.stderr}"

    output_lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
    expected_paths = [
        "/home/user/data/raw_d.txt",
        "/home/user/data/raw_e.txt",
        "/home/user/data/raw_f.txt"
    ]

    unique_output_paths = sorted(list(set(output_lines)))
    assert unique_output_paths == expected_paths, \
        f"Expected paths {expected_paths}, but got {unique_output_paths} from trace.py output."


def test_exact_argument_counts():
    for command in (["python3", TRACE], ["python3", TRACE, "one", "two"],
                    ["bash", SUMMARIZE], ["bash", SUMMARIZE, "one", "two"]):
        result = run(command)
        assert result.returncode != 0, f"Command unexpectedly accepted the wrong argument count: {command}"


def test_dynamic_lineage_and_executed_parameterized_recursive_cte():
    token = uuid.uuid4().hex
    work = tempfile.mkdtemp(prefix="lineage_" + token + "_", dir="/tmp")
    backup = os.path.join(work, "original.db")
    replacement = os.path.join(work, "dynamic.db")
    hookdir = os.path.join(work, "hook")
    sql_log = os.path.join(work, "sql.jsonl")
    os.mkdir(hookdir)
    shutil.copy2(DB, backup)

    names = {
        1: "raw_alpha_" + token,
        2: "raw_beta_" + token,
        3: "raw_gamma_" + token,
        4: "middle_left_" + token,
        5: "middle_right_" + token,
        6: "target_'_" + token,
        7: "unrelated_raw_" + token,
        8: "unrelated_derived_" + token,
    }
    paths = {
        1: os.path.join(work, "z_source.txt"),
        2: os.path.join(work, "a_source.txt"),
        3: os.path.join(work, "m_source.txt"),
        4: os.path.join(work, "middle_left.txt"),
        5: os.path.join(work, "middle_right.txt"),
        6: os.path.join(work, "target.txt"),
        7: os.path.join(work, "unrelated.txt"),
        8: os.path.join(work, "unrelated_derived.txt"),
    }
    contents = {
        paths[1]: "dynamic alpha " + token + "\n",
        paths[2]: "dynamic beta " + token + "\n",
        paths[3]: "dynamic gamma " + token + "\n",
        paths[7]: "unrelated " + token + "\n",
    }
    for path, content in contents.items():
        with open(path, "w") as f:
            f.write(content)

    edges = [(1, 4), (2, 4), (2, 5), (3, 5), (4, 6), (5, 6), (7, 8)]
    conn = sqlite3.connect(replacement)
    conn.executescript("""
        CREATE TABLE datasets (id INTEGER PRIMARY KEY, name TEXT UNIQUE, file_path TEXT);
        CREATE TABLE dependencies (source_id INTEGER, derived_id INTEGER);
    """)
    conn.executemany("INSERT INTO datasets(id, name, file_path) VALUES (?, ?, ?)",
                     [(i, names[i], paths[i]) for i in sorted(names)])
    conn.executemany("INSERT INTO dependencies(source_id, derived_id) VALUES (?, ?)", edges)
    conn.commit()
    conn.close()

    # Instrument sqlite3 in the trace subprocess so the verifier observes the
    # SQL that is actually executed, rather than trusting a source-code grep.
    hook = r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_log = os.environ.get("TRACE_SQL_LOG")

def _record(sql, parameters):
    try:
        has_parameters = bool(parameters)
    except Exception:
        has_parameters = True
    with open(_log, "a") as f:
        f.write(json.dumps({"sql": str(sql), "has_parameters": has_parameters}) + "\\n")

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, "_cursor", cursor)
    def execute(self, sql, parameters=()):
        _record(sql, parameters)
        self._cursor.execute(sql, parameters)
        return self
    def executemany(self, sql, parameters):
        return self._cursor.executemany(sql, parameters)
    def __iter__(self):
        return iter(self._cursor)
    def __getattr__(self, name):
        return getattr(self._cursor, name)
    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)
    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))
    def execute(self, sql, parameters=()):
        _record(sql, parameters)
        return CursorProxy(self._connection.execute(sql, parameters))
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)
    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
'''
    with open(os.path.join(hookdir, "sitecustomize.py"), "w") as f:
        f.write(hook)

    incoming = {}
    for source, derived in edges:
        incoming.setdefault(derived, []).append(source)

    def expected_for(target_id):
        seen = set()
        stack = [target_id]
        while stack:
            current = stack.pop()
            if current in seen:
                continue
            seen.add(current)
            stack.extend(incoming.get(current, []))
        return sorted(paths[i] for i in seen if i not in incoming)

    try:
        os.replace(replacement, DB)
        env = os.environ.copy()
        env["PYTHONPATH"] = hookdir + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["TRACE_SQL_LOG"] = sql_log

        for target_id in (6, 4, 5):
            result = run(["python3", TRACE, names[target_id]], env=env)
            assert result.returncode == 0, result.stderr
            actual = [line.strip() for line in result.stdout.splitlines() if line.strip()]
            assert actual == expected_for(target_id), \
                f"Incorrect dynamic lineage for {names[target_id]}: {actual}"

        assert os.path.isfile(sql_log), "trace.py did not execute observable SQLite statements"
        with open(sql_log) as f:
            records = [json.loads(line) for line in f if line.strip()]
        recursive = [r for r in records if re.search(r"\bWITH\s+RECURSIVE\b", r["sql"], re.I)]
        assert recursive, "trace.py did not actually execute a Recursive CTE"
        assert any(r["has_parameters"] and re.search(r"\?|[:@$][A-Za-z_]\w*", r["sql"])
                   for r in recursive), \
            "The executed Recursive CTE was not parameterized"

        with open(SUMMARY, "w") as f:
            f.write("stale fabricated summary\n")
        result = run(["bash", SUMMARIZE, names[6]])
        assert result.returncode == 0, f"summarize.sh failed: {result.stderr}"
        with open(SUMMARY, "r") as f:
            actual_summary = f.read()
        expected_summary = "".join(contents[p] for p in expected_for(6))
        assert actual_summary == expected_summary, \
            f"summarize.sh produced incorrect concatenated content: {actual_summary!r}"
    finally:
        if os.path.exists(backup):
            os.replace(backup, DB)
        shutil.rmtree(work, ignore_errors=True)


def test_summarize_really_chains_trace_output_and_quotes_argument():
    work = tempfile.mkdtemp(prefix="summary_chain_", dir="/tmp")
    trace_backup = os.path.join(work, "trace.backup")
    marker = os.path.join(work, "called")
    first = os.path.join(work, "first file.txt")
    second = os.path.join(work, "second file.txt")
    target = "target with spaces ' and symbols"
    shutil.copy2(TRACE, trace_backup)
    original_mode = stat.S_IMODE(os.stat(TRACE).st_mode)
    with open(first, "w") as f:
        f.write("first chained content\n")
    with open(second, "w") as f:
        f.write("second chained content\n")

    stub = f'''import pathlib
import sys
if len(sys.argv) != 2 or sys.argv[1] != {target!r}:
    raise SystemExit(23)
pathlib.Path({marker!r}).write_text("called")
print({first!r})
print({second!r})
'''
    try:
        with open(TRACE, "w") as f:
            f.write(stub)
        os.chmod(TRACE, original_mode)
        with open(SUMMARY, "w") as f:
            f.write("stale\n")
        result = run(["bash", SUMMARIZE, target])
        assert result.returncode == 0, f"summarize.sh did not successfully chain trace.py: {result.stderr}"
        assert os.path.isfile(marker), "summarize.sh did not call python3 /home/user/trace.py"
        with open(SUMMARY) as f:
            assert f.read() == "first chained content\nsecond chained content\n"
    finally:
        shutil.copy2(trace_backup, TRACE)
        os.chmod(TRACE, original_mode)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
