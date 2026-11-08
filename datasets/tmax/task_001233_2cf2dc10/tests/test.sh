#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import pytest

PROFILER_DIR = "/home/user/profiler"
LOGS_DB = os.path.join(PROFILER_DIR, "logs.db")
LOGS_DB_WAL = os.path.join(PROFILER_DIR, "logs.db-wal")
PROCESS_PY = os.path.join(PROFILER_DIR, "process.py")
SUMMARY_JSON = os.path.join(PROFILER_DIR, "summary.json")
TRACE_LOG = os.path.join(PROFILER_DIR, "trace.log")


def run_process():
    result = subprocess.run(
        [sys.executable, PROCESS_PY],
        cwd=PROFILER_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"process.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def clear_outputs():
    for path in (SUMMARY_JSON, TRACE_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def test_db_recovery():
    assert not os.path.exists(LOGS_DB_WAL), "logs.db-wal still exists. The WAL was not properly checkpointed and removed."

    conn = sqlite3.connect(LOGS_DB)
    cursor = conn.cursor()
    cursor.execute("PRAGMA journal_mode;")
    mode = cursor.fetchone()[0]
    conn.close()

    assert mode.lower() == "delete", f"Expected journal_mode to be 'delete', but got '{mode}'."


def test_process_py_fixed():
    assert os.path.isfile(PROCESS_PY), f"File {PROCESS_PY} is missing."
    with open(PROCESS_PY, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "get_lock" in content, "process.py does not appear to use .get_lock() for safe concurrent updates."
    assert "'q'" in content or '"q"' in content, "process.py does not appear to use a 64-bit integer ('q') for multiprocessing.Value."
    assert "'i'" not in content and '"i"' not in content, "process.py still contains the 32-bit integer ('i') which causes OverflowError."

    try:
        tree = ast.parse(content, filename=PROCESS_PY)
    except SyntaxError as exc:
        pytest.fail(f"process.py is not valid Python: {exc}")

    process_chunks = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "process_chunk"
    ]
    assert process_chunks, "process.py does not define process_chunk."
    process_chunk = process_chunks[0]

    parents = {}
    for node in ast.walk(process_chunk):
        for child in ast.iter_child_nodes(node):
            parents[child] = node

    shared_names = {"total_metric", "processed_count"}
    updates = {name: [] for name in shared_names}
    for node in ast.walk(process_chunk):
        if (
            isinstance(node, ast.AugAssign)
            and isinstance(node.target, ast.Attribute)
            and node.target.attr == "value"
            and isinstance(node.target.value, ast.Name)
            and node.target.value.id in shared_names
        ):
            updates[node.target.value.id].append(node)

    def enclosing_get_locks(node):
        locks = set()
        current = parents.get(node)
        while current is not None:
            if isinstance(current, ast.With):
                for item in current.items:
                    expr = item.context_expr
                    if (
                        isinstance(expr, ast.Call)
                        and isinstance(expr.func, ast.Attribute)
                        and expr.func.attr == "get_lock"
                        and isinstance(expr.func.value, ast.Name)
                        and expr.func.value.id in shared_names
                    ):
                        locks.add(expr.func.value.id)
            current = parents.get(current)
        return locks

    for name in shared_names:
        assert updates[name], f"process_chunk does not update {name}.value."
        for update in updates[name]:
            assert enclosing_get_locks(update), (
                f"The update to {name}.value is not enclosed by a shared value's get_lock() context."
            )

    value_types = {}
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        value = node.value
        if not (
            isinstance(value, ast.Call)
            and isinstance(value.func, ast.Attribute)
            and value.func.attr == "Value"
            and value.args
            and isinstance(value.args[0], ast.Constant)
        ):
            continue
        for target in targets:
            if isinstance(target, ast.Name) and target.id in shared_names:
                value_types[target.id] = value.args[0].value

    assert value_types.get("total_metric") == "q", "total_metric must be created with multiprocessing.Value('q', ...)."
    assert value_types.get("processed_count") == "q", "processed_count must be created with multiprocessing.Value('q', ...)."

    process_calls = []
    for node in ast.walk(tree):
        if not (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "Process"
        ):
            continue
        target_kw = next((kw.value for kw in node.keywords if kw.arg == "target"), None)
        args_kw = next((kw.value for kw in node.keywords if kw.arg == "args"), None)
        arg_names = {n.id for n in ast.walk(args_kw)} if args_kw is not None else set()
        if (
            isinstance(target_kw, ast.Name)
            and target_kw.id == "process_chunk"
            and shared_names.issubset(arg_names)
        ):
            process_calls.append(node)
    assert process_calls, "process_chunk must actually be launched by multiprocessing.Process with both shared values."


def test_process_behavior_on_derived_input():
    fd, backup_path = tempfile.mkstemp(prefix="logs-db-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(LOGS_DB, backup_path)

    failure = None
    try:
        rng = random.SystemRandom()
        traced_ids = {100 * n for n in rng.sample(range(1, 1000), 13)}
        nontraced_pool = [n for n in range(1, 100000) if n % 100 != 0]
        other_ids = set(rng.sample(nontraced_pool, 974))
        ids = list(traced_ids | other_ids)
        rng.shuffle(ids)
        rows = [(row_id, rng.randint(2200000, 4900000)) for row_id in ids]

        conn = sqlite3.connect(LOGS_DB)
        try:
            mode = conn.execute("PRAGMA journal_mode=DELETE").fetchone()[0]
            assert mode.lower() == "delete"
            conn.execute("DELETE FROM logs")
            conn.executemany("INSERT INTO logs (id, metric) VALUES (?, ?)", rows)
            conn.commit()
            expected_count, expected_metric = conn.execute(
                "SELECT COUNT(*), COALESCE(SUM(metric), 0) FROM logs"
            ).fetchone()
            expected_trace = [
                row[0] for row in conn.execute(
                    "SELECT id FROM logs WHERE id % 100 = 0 ORDER BY id"
                ).fetchall()
            ]
        finally:
            conn.close()

        clear_outputs()
        run_process()

        assert os.path.isfile(SUMMARY_JSON), "process.py did not generate summary.json when executed."
        with open(SUMMARY_JSON, "r") as f:
            generated_summary = json.load(f)
        assert generated_summary.get("total_records") == expected_count, (
            f"On verifier-generated data, expected total_records={expected_count}, "
            f"got {generated_summary.get('total_records')}."
        )
        assert generated_summary.get("total_metric") == expected_metric, (
            f"On verifier-generated data, expected total_metric={expected_metric}, "
            f"got {generated_summary.get('total_metric')}."
        )

        assert os.path.isfile(TRACE_LOG), "process.py did not generate trace.log when executed."
        with open(TRACE_LOG, "r") as f:
            generated_lines = f.read().strip().splitlines()
        try:
            generated_trace = sorted(int(line.strip()) for line in generated_lines)
        except ValueError:
            pytest.fail("trace.log contains non-integer values on verifier-generated data.")
        assert generated_trace == expected_trace, (
            f"On verifier-generated data, expected traced IDs {expected_trace}, got {generated_trace}."
        )
    except BaseException as exc:
        failure = exc
    finally:
        for suffix in ("-wal", "-shm"):
            try:
                os.remove(LOGS_DB + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup_path, LOGS_DB)
        os.remove(backup_path)
        clear_outputs()
        try:
            run_process()
        except BaseException as restore_exc:
            if failure is None:
                failure = restore_exc

    if failure is not None:
        raise failure


def test_summary_json():
    assert os.path.isfile(SUMMARY_JSON), f"File {SUMMARY_JSON} was not generated."

    with open(SUMMARY_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SUMMARY_JSON} is not a valid JSON file.")

    assert data.get("total_records") == 1000, f"Expected total_records to be 1000, got {data.get('total_records')}."
    assert data.get("total_metric") == 2500000000, f"Expected total_metric to be 2500000000, got {data.get('total_metric')}."


def test_trace_log():
    assert os.path.isfile(TRACE_LOG), f"File {TRACE_LOG} was not created."

    with open(TRACE_LOG, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 10, f"Expected exactly 10 lines in trace.log, got {len(lines)}."

    try:
        ids = sorted([int(line.strip()) for line in lines])
    except ValueError:
        pytest.fail("trace.log contains non-integer values.")

    expected_ids = list(range(100, 1001, 100))
    assert ids == expected_ids, f"Expected traced IDs to be {expected_ids}, but got {ids}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
