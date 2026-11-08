#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

SCRIPT = "/home/user/clean_data.py"
WRAPPER = "/home/user/run_job.sh"
DB = "/home/user/cleaned_data.db"
LOG = "/home/user/pipeline_errors.log"
RAW = Path("/home/user/raw_data")


def run_wrapper(env=None, timeout=30):
    result = subprocess.run(
        [WRAPPER],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"run_job.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_once():
    for path in (DB, LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    run_wrapper()


def test_python_script_exists():
    assert os.path.isfile("/home/user/clean_data.py"), "/home/user/clean_data.py does not exist."


def test_bash_wrapper_exists_and_executable():
    path = "/home/user/run_job.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."


def test_cron_schedule_correct():
    path = "/home/user/schedule.cron"
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    pattern = r"30\s+2\s+\*\s+\*\s+\*\s+/home/user/run_job\.sh"
    assert re.search(pattern, content), f"{path} does not contain the correct cron schedule for 2:30 AM."


def test_database_contents():
    db_path = "/home/user/cleaned_data.db"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='feedback';")
    assert cursor.fetchone() is not None, "Table 'feedback' does not exist in the database."

    cursor.execute("SELECT id FROM feedback ORDER BY id;")
    rows = cursor.fetchall()
    ids = [row[0] for row in rows]
    expected_ids = ["101", "102", "201", "203", "302"]

    assert ids == expected_ids, f"Database does not contain the expected rows. Found IDs: {ids}"

    cursor.execute("SELECT id, user, text FROM feedback ORDER BY id;")
    assert cursor.fetchall() == [
        ("101", "alice", "Great service!"),
        ("102", "bob", "I love the new features."),
        ("201", "charlie", "Not bad."),
        ("203", "eve", "All good now."),
        ("302", "grace", "Perfect!"),
    ]
    conn.close()


def test_error_log_contents():
    log_path = "/home/user/pipeline_errors.log"
    assert os.path.isfile(log_path), f"Error log {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in error log, found {len(lines)}."

    expected_line1 = '[data2.jsonl] Line 2: {"id": "202", "user": "diana", "text": "Broken unicode \\u28ZZ here."}'
    expected_line2 = '[data3.jsonl] Line 1: {"id": "301", "user": "frank", "text": "Missing escape \\u1"}'

    assert expected_line1 in lines, "Missing expected error log entry for data2.jsonl."
    assert expected_line2 in lines, "Missing expected error log entry for data3.jsonl."


def test_implementation_uses_required_apis():
    source = Path(SCRIPT).read_text(encoding="utf-8")
    tree = ast.parse(source, filename=SCRIPT)

    parallel_imported = False
    parallel_names = set()
    json_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "json":
                    json_names.add(alias.asname or "json")
                if alias.name == "multiprocessing" or alias.name.startswith("multiprocessing."):
                    parallel_imported = True
                if alias.name == "concurrent.futures" or alias.name.startswith("concurrent.futures."):
                    parallel_imported = True
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            if module == "json":
                for alias in node.names:
                    if alias.name == "loads":
                        json_names.add(alias.asname or alias.name)
            if module == "multiprocessing" or module.startswith("multiprocessing.") or module == "concurrent.futures" or module.startswith("concurrent.futures."):
                parallel_imported = True
                for alias in node.names:
                    if alias.name in {"Pool", "Process", "ProcessPoolExecutor", "ThreadPoolExecutor"}:
                        parallel_names.add(alias.asname or alias.name)

    calls = [node.func for node in ast.walk(tree) if isinstance(node, ast.Call)]
    uses_json_loads = any(
        (isinstance(func, ast.Attribute) and func.attr == "loads")
        or (isinstance(func, ast.Name) and func.id in json_names)
        for func in calls
    )
    uses_parallel_worker = any(
        (isinstance(func, ast.Attribute) and func.attr in {"Pool", "Process", "ProcessPoolExecutor", "ThreadPoolExecutor"})
        or (isinstance(func, ast.Name) and func.id in parallel_names)
        for func in calls
    )
    uses_executemany = any(isinstance(func, ast.Attribute) and func.attr == "executemany" for func in calls)

    assert uses_json_loads, "clean_data.py must parse input lines with json.loads()."
    assert parallel_imported and uses_parallel_worker, "clean_data.py must use multiprocessing or concurrent.futures workers."
    assert uses_executemany, "clean_data.py must use SQLite executemany() for bulk insertion."


def test_zz_dynamic_pipeline_and_parallel_execution():
    token = uuid.uuid4().hex
    temp_root = Path(tempfile.mkdtemp(prefix="pipeline_verify_"))
    original_raw = temp_root / "original_raw_data"
    trace_dir = temp_root / "instrumentation"
    trace_dir.mkdir()
    trace_file = temp_root / "json_load_contexts.txt"

    os.rename(RAW, original_raw)
    RAW.mkdir()

    expected_rows = []
    expected_errors = []
    try:
        for i in range(16):
            filename = f"batch_{token}_{i:02d}.jsonl"
            lines = []
            for j in range(2):
                record = {
                    "id": f"{token}-{i}-{j}",
                    "user": f"user {i}/{j} Ω",
                    "text": f"dynamic text {token} {i}:{j} — ✓",
                }
                lines.append(json.dumps(record, ensure_ascii=False))
                expected_rows.append((record["id"], record["user"], record["text"]))
            if i % 3 == 0:
                bad = '{"id": "bad-' + token + f'-{i}", "user": "broken", "text": "invalid \\u12G4"}}'
                lines.append(bad)
                expected_errors.append(f"[{filename}] Line 3: {bad}")
            (RAW / filename).write_text("\n".join(lines) + "\n", encoding="utf-8")

        sitecustomize = (
            "import json, os, threading, time\n"
            "_real_loads = json.loads\n"
            "def _traced_loads(*args, **kwargs):\n"
            "    path = os.environ.get('PIPELINE_JSON_TRACE')\n"
            "    if path:\n"
            "        line = ('%s:%s\\n' % (os.getpid(), threading.get_ident())).encode()\n"
            "        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)\n"
            "        try: os.write(fd, line)\n"
            "        finally: os.close(fd)\n"
            "        time.sleep(0.015)\n"
            "    return _real_loads(*args, **kwargs)\n"
            "json.loads = _traced_loads\n"
        )
        (trace_dir / "sitecustomize.py").write_text(sitecustomize, encoding="utf-8")

        for path in (DB, LOG):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env["PIPELINE_JSON_TRACE"] = str(trace_file)
        env["PYTHONPATH"] = str(trace_dir) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        run_wrapper(env=env, timeout=45)

        assert os.path.isfile(DB), "Pipeline did not create cleaned_data.db."
        with sqlite3.connect(DB) as conn:
            columns = conn.execute("PRAGMA table_info(feedback)").fetchall()
            assert [(row[1], row[2].upper()) for row in columns] == [
                ("id", "TEXT"), ("user", "TEXT"), ("text", "TEXT")
            ], "feedback must have exactly the id, user, and text TEXT columns."
            actual_rows = conn.execute("SELECT id, user, text FROM feedback ORDER BY id").fetchall()
        assert actual_rows == sorted(expected_rows), "Dynamic records, including user/text values, were not loaded correctly."

        assert os.path.isfile(LOG), "Pipeline did not create pipeline_errors.log."
        actual_errors = [line.strip() for line in Path(LOG).read_text(encoding="utf-8").splitlines() if line.strip()]
        assert sorted(actual_errors) == sorted(expected_errors), "Malformed dynamic lines were not logged in the required format."

        assert trace_file.is_file(), "No calls to json.loads() were observed while processing dynamic input."
        contexts = {line.strip() for line in trace_file.read_text().splitlines() if line.strip()}
        assert len(contexts) >= 2, "All json.loads() calls occurred in one process/thread; files were not processed in parallel."
    finally:
        if RAW.exists():
            shutil.rmtree(RAW)
        os.rename(original_raw, RAW)
        shutil.rmtree(temp_root, ignore_errors=True)


def test_zzz_wrapper_executes_clean_data_script():
    marker = Path(tempfile.mktemp(prefix="wrapper_marker_"))
    original = Path(SCRIPT).read_bytes()
    original_mode = os.stat(SCRIPT).st_mode
    sentinel = (
        "#!/usr/bin/env python3\n"
        "import os\n"
        "open(os.environ['PIPELINE_WRAPPER_MARKER'], 'w').write('executed')\n"
    )
    try:
        Path(SCRIPT).write_text(sentinel, encoding="utf-8")
        os.chmod(SCRIPT, original_mode | stat.S_IXUSR)
        env = os.environ.copy()
        env["PIPELINE_WRAPPER_MARKER"] = str(marker)
        run_wrapper(env=env)
        assert marker.read_text() == "executed", "run_job.sh does not execute /home/user/clean_data.py."
    finally:
        Path(SCRIPT).write_bytes(original)
        os.chmod(SCRIPT, original_mode)
        try:
            marker.unlink()
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
